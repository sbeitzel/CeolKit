import Foundation
import CeolKitModel

/// One notehead a staff is about to draw, reduced to what deciding a collision needs.
///
/// Built by whoever is about to draw — or to reserve room for — the head, because "the same
/// note" is a question about the *ink*: two voices share a notehead when the glyph, the dot
/// and the accidental they would each draw are identical, whatever the durations behind them
/// were written as.
struct CollisionHead {
    let voiceIndex: Int
    /// Diatonic staff position, as ``SVGEmitter`` counts it: one per step, rising.
    let staffPos: Int
    /// Which of the three notehead glyphs is drawn.
    let glyph: SMuFLGlyph
    let isDotted: Bool
    let accidental: Alteration?
    /// Which way this head's voice stems, already resolved.  Only the *direction* a displaced
    /// unison moves depends on it; whether anything moves at all does not, which is what lets
    /// ``SharedStaffMerger`` ask that question before stem directions are known.
    let stemUp: Bool

    /// Which line or space a pitch is drawn on: one per diatonic step, rising, zero on the
    /// bottom line of a treble staff.  Only differences between two heads on one staff matter
    /// here, so the origin is arbitrary — but it is the emitter's, so both agree.
    static func staffPosition(of pitch: Pitch) -> Int {
        (pitch.octave - 4) * 7 + (pitch.step.rawValue - DiatonicStep.e.rawValue)
    }

    /// Two heads that draw the same ink in the same place, and so need only be drawn once.
    func drawsSameInk(as other: CollisionHead) -> Bool {
        staffPos == other.staffPos && glyph == other.glyph && isDotted == other.isDotted
            && accidental == other.accidental
    }
}

/// Where one head, and the marks that belong to it, are drawn once its column's collisions
/// are resolved.
///
/// Every offset is relative to the column's own x — the onset every voice in it shares — so
/// the caller adds its own origin and nothing here knows about the page.
struct HeadPlacement {
    /// Horizontal displacement of the notehead, and with it the stem, the flag and the
    /// ledger lines.  Negative is left.
    var dx: Double = 0
    /// `true` where another voice draws this very notehead.  The head, its accidental, its
    /// dot and its ledger lines are that voice's; this one draws only its stem, which is what
    /// tells a reader two parts are sounding the note.
    var isShared: Bool = false
    /// x of the augmentation dot relative to the column, where the column moved it out of
    /// its default place beside the notehead.
    var dotDX: Double?
    /// How far the augmentation dot moves from where the notehead alone would put it,
    /// positive downward, where two dots would otherwise land on the same spot.
    var dotDY: Double?
    /// x the accidental is drawn *left of*, relative to the column, where the column moved it
    /// off its own notehead's edge.
    var accidentalAnchorDX: Double?

    /// What every head on a staff no one shares gets: drawn exactly where it was placed.
    static let unmoved = HeadPlacement()
}

/// Resolves the notehead collisions of one column — one onset — of a staff several voices
/// share (ABC v2.2 §11.1, issue #79).
///
/// Two voices on one staff sound together by definition, so their heads land at one x, and
/// four things can collide there: the heads themselves at a unison or a second, their
/// augmentation dots, and their accidentals.  Each is resolved the way `abcm2ps -g` resolves
/// it, which is the way an engraver does:
///
/// - **Unison.**  Where both voices would draw the same ink — same staff position, same
///   notehead, same dot, same accidental — one head is drawn and both stems grow from it.
///   Where they would not, the heads are set side by side, the stem-down voice's to the
///   left, so that each stem leaves the pair on its own side and neither runs through the
///   other's head.
/// - **Second.**  The lower-pitched head moves right by its own width.  The two stems then
///   nearly coincide, which is what a second between parts looks like in print.
/// - **Dots.**  Every dot in the column is drawn in one vertical strip right of the
///   *rightmost* head, so a displaced head cannot be written over by its partner's dot; two
///   that would then land on the same spot are split, the lower one taking the space below
///   its note instead of the one above.
/// - **Accidentals.**  All of them hang off the *leftmost* head rather than each off its own,
///   and any two whose glyphs would overlap vertically are stacked, the lower one further
///   left.  Vertical overlap is measured from the glyphs' own bounding boxes: accidentals
///   differ in height as well as width, and a fixed threshold would stack pairs that clear
///   each other and let pairs that do not through.
///
/// ## Where this parts company with abcm2ps
///
/// abcm2ps displaces a unison the voices cannot share to the *right* when what differs is the
/// accidental, and draws that accidental on top of the displaced notehead — legibly wrong,
/// and the reason it is not copied.  A unison always separates leftward here, whatever it was
/// that stopped the voices sharing.
struct NoteheadCollisions {
    let noteheadWidth: Double
    let staffSize: Double
    let accidentalMetrics: AccidentalMetrics
    let metadata: BravuraMetadata

    /// Gap between a notehead's right edge and its augmentation dot.  Matches
    /// ``SVGEmitter/emitAugmentationDot(x:noteheadY:staffPos:fontSize:builder:)``, which is
    /// what draws the dot when no collision moves it.
    private var dotGap: Double { noteheadWidth * 0.2 }

    // MARK: - Resolution

    /// Resolves `heads` — every notehead one column of a shared staff draws, in the order
    /// they will be drawn — into one placement each.
    func resolve(_ heads: [CollisionHead]) -> [HeadPlacement] {
        var placements = [HeadPlacement](repeating: .unmoved, count: heads.count)
        guard Set(heads.map(\.voiceIndex)).count > 1 else { return placements }

        let (shared, dx) = Self.shareAndDisplace(heads, noteheadWidth: noteheadWidth)
        for i in heads.indices {
            placements[i].isShared = shared[i]
            placements[i].dx = dx[i]
        }

        let visible = heads.indices.filter { !shared[$0] }
        if dx.contains(where: { $0 != 0 }) {
            placeDots(heads, visible: visible, dx: dx, into: &placements)
        }
        placeAccidentals(heads, visible: visible, dx: dx, into: &placements)
        return placements
    }

    /// How much room a column's collisions need on each side of it, beyond what the notes in
    /// it claim for themselves.
    ///
    /// ``SharedStaffMerger`` asks this before it places the heads: a head displaced by its own
    /// width into a column sized for one is drawn over whatever stands next to it — over the
    /// following note where a second sends it right, and over the bar line or the note behind
    /// it where a unison sends it left.
    ///
    /// Which of two heads gives way depends on how they stem; that one of them does, and
    /// which way it goes, does not — so this answer is the same whatever stem directions the
    /// caller has filled in, and can be had before they are known.
    static func extraWidth(_ heads: [CollisionHead], noteheadWidth: Double)
        -> (left: Double, right: Double) {
        guard Set(heads.map(\.voiceIndex)).count > 1 else { return (0, 0) }
        let dx = shareAndDisplace(heads, noteheadWidth: noteheadWidth).dx
        return (left: -min(dx.min() ?? 0, 0), right: max(dx.max() ?? 0, 0))
    }

    // MARK: - Heads

    /// Which heads are drawn by another voice, and how far the rest move sideways.
    ///
    /// Voice order decides who keeps the place: the upper voice's head is the one drawn, and
    /// the one left where the sizer put it.
    private static func shareAndDisplace(_ heads: [CollisionHead], noteheadWidth: Double)
        -> (shared: [Bool], dx: [Double]) {
        let order = heads.indices.sorted {
            (heads[$0].voiceIndex, -heads[$0].staffPos) < (heads[$1].voiceIndex, -heads[$1].staffPos)
        }
        var shared = [Bool](repeating: false, count: heads.count)
        var dx = [Double](repeating: 0, count: heads.count)

        for (n, i) in order.enumerated() where !shared[i] {
            for j in order[(n + 1)...] where !shared[j] {
                guard heads[j].voiceIndex != heads[i].voiceIndex else { continue }
                if heads[i].drawsSameInk(as: heads[j]) { shared[j] = true }
            }
        }

        let visible = order.filter { !shared[$0] }
        for (n, a) in visible.enumerated() {
            for b in visible[(n + 1)...] {
                guard heads[a].voiceIndex != heads[b].voiceIndex else { continue }
                let interval = heads[a].staffPos - heads[b].staffPos
                // Anything a third or more apart clears on its own, and a pair one of whose
                // heads has already moved is already apart.
                guard abs(interval) <= 1, dx[a] == dx[b] else { continue }
                if interval == 0 {
                    // A unison the voices cannot share: side by side, each stem on its own
                    // side of the pair.  Where both stem the same way — two voices that both
                    // asked for `stem=` — the lower voice gives way.
                    let mover = heads[a].stemUp == heads[b].stemUp
                        ? (heads[a].voiceIndex > heads[b].voiceIndex ? a : b)
                        : (heads[a].stemUp ? b : a)
                    dx[mover] = -noteheadWidth
                } else {
                    dx[interval < 0 ? a : b] = noteheadWidth
                }
            }
        }
        return (shared, dx)
    }

    // MARK: - Dots

    /// Aligns the column's augmentation dots right of its rightmost head, and splits any two
    /// that would land on the same spot.
    private func placeDots(_ heads: [CollisionHead], visible: [Int], dx: [Double],
                           into placements: inout [HeadPlacement]) {
        // Highest first, and the upper voice first where two heads are at one pitch: whoever
        // is served first keeps the dot where the notehead alone would have put it.
        let dotted = visible.filter { heads[$0].isDotted }.sorted {
            (-heads[$0].staffPos, heads[$0].voiceIndex) < (-heads[$1].staffPos, heads[$1].voiceIndex)
        }
        guard !dotted.isEmpty else { return }

        let dotDX = (visible.map { dx[$0] }.max() ?? 0) + noteheadWidth + dotGap
        // Where each dot sits, in half staff spaces: beside a note in a space, and lifted
        // into the space above one on a line.
        var taken: Set<Int> = []
        for i in dotted {
            placements[i].dotDX = dotDX
            let pos = heads[i].staffPos
            let preferred = pos.isMultiple(of: 2) ? pos + 1 : pos
            let alternative = pos.isMultiple(of: 2) ? pos - 1 : pos - 2
            let chosen = taken.contains(preferred) && !taken.contains(alternative)
                ? alternative : preferred
            taken.insert(chosen)
            // Positive is downward, and a half space of staff position is half a staff space.
            placements[i].dotDY = Double(preferred - chosen) * staffSize / 2.0
        }
    }

    // MARK: - Accidentals

    /// Hangs the column's accidentals off its leftmost head, stacking any that would overlap.
    private func placeAccidentals(_ heads: [CollisionHead], visible: [Int], dx: [Double],
                                  into placements: inout [HeadPlacement]) {
        let accidentals = visible.filter { heads[$0].accidental != nil }.sorted {
            (-heads[$0].staffPos, heads[$0].voiceIndex) < (-heads[$1].staffPos, heads[$1].voiceIndex)
        }
        guard accidentals.count > 1 || dx.contains(where: { $0 != 0 }) else { return }

        let anchor = visible.map { dx[$0] }.min() ?? 0
        var slots: [[Int]] = []
        var slotWidths: [Double] = []
        for i in accidentals {
            guard let alteration = heads[i].accidental else { continue }
            var slot = 0
            while slot < slots.count,
                  slots[slot].contains(where: { overlapsVertically(heads[$0], heads[i]) }) {
                slot += 1
            }
            if slot == slots.count { slots.append([]); slotWidths.append(0) }
            slots[slot].append(i)
            slotWidths[slot] = max(slotWidths[slot], accidentalMetrics.offset(for: alteration))
        }
        // Assigned only once every slot's width is known: a slot is as wide as the widest
        // accidental in it, and the one to its left hangs off that.
        for (slot, members) in slots.enumerated() {
            let step = slotWidths[..<slot].reduce(0, +)
            for i in members { placements[i].accidentalAnchorDX = anchor - step }
        }
    }

    /// Whether the accidentals of two heads would run into each other vertically.
    private func overlapsVertically(_ a: CollisionHead, _ b: CollisionHead) -> Bool {
        guard let aExtent = accidentalExtent(a), let bExtent = accidentalExtent(b) else {
            return false
        }
        let clearance = 0.1 * staffSize
        return aExtent.lowerBound - clearance < bExtent.upperBound
            && bExtent.lowerBound - clearance < aExtent.upperBound
    }

    /// The vertical span an accidental glyph covers, in page coordinates relative to the
    /// staff's own zero — y grows downward, the glyph's bounding box grows upward.
    private func accidentalExtent(_ head: CollisionHead) -> ClosedRange<Double>? {
        guard let alteration = head.accidental,
              let glyph = SMuFLGlyph.accidental(for: alteration) else { return nil }
        let box = metadata.glyphBBoxes[glyph.rawValue]
        let y = -Double(head.staffPos) * staffSize / 2.0
        let top = y - (box?.neY ?? 1.4) * staffSize
        let bottom = y - (box?.swY ?? -1.4) * staffSize
        return top...bottom
    }
}

extension SMuFLGlyph {
    /// The notehead drawn for a duration in whole notes.
    static func notehead(absoluteDuration d: Double) -> SMuFLGlyph {
        if d >= 1.0 { return .noteheadWhole }
        if d >= 0.5 { return .noteheadHalf  }
        return .noteheadBlack
    }
}
