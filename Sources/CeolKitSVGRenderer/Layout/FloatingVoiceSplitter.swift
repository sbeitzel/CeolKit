import Foundation
import CeolKitModel

/// Cuts a floating voice (`%%score {RH *M| LH}`, ABC v2.2 §11.1) into the two ordinary
/// voices the rest of the layout can draw: one tenanting the staff above, one the staff
/// below.
///
/// Nothing downstream of here knows what a floating voice is, and it does not have to.  A
/// staff already carries more than one voice — that is what a `( … )` group is — so a
/// floating voice becomes a second (or third) tenant of each of its neighbours, and the
/// merge onto a common onset grid (#76), the opposed stems (#77) and the displaced unisons
/// (#79) all apply to it unchanged.
///
/// **The silent half keeps the time.**  Where an atom goes to the staff below, the staff
/// above gets an invisible rest of exactly that duration, so both halves still measure the
/// bar the same way and every later onset lands where it sounds.  Adjacent displacements
/// collapse into one rest, and a displacement that runs to the end of a bar gets none at all:
/// nothing follows it to be pushed out of place, and an unneeded rest would claim a column
/// the music never asked for.
///
/// **Both halves keep the voice's id.**  Selection has already finished with ids by the time
/// this runs, and the two halves *are* one voice: the diagnostics that name it should name it
/// once, whichever staff the note in question ended up on.
enum FloatingVoiceSplitter {

    /// The two voices a floating voice is drawn as.
    struct Halves {
        /// Drawn on the staff above, as its lowest part.
        let above: Voice
        /// Drawn on the staff below, as its highest part.
        let below: Voice
    }

    /// - Parameters:
    ///   - voice: the floating voice, whole.
    ///   - split: the diatonic index at or above which music belongs on the staff above; see
    ///     ``FloatingVoiceAssigner/split(middle:above:below:)``.
    static func split(_ voice: Voice, at split: Int) -> Halves {
        let atoms = atoms(of: voice)
        let staves = FloatingVoiceAssigner.assign(
            atoms: atoms.map { FloatingVoiceAssigner.Atom(steps: steps(at: $0, in: voice)) },
            split: split)

        // Per-event, in the shape the rebuild reads it: `placement[stave][measure][event]`.
        var placement = voice.staves.map { stave in
            stave.measures.map { [FloatingVoiceAssigner.Staff](repeating: .above,
                                                               count: $0.events.count) }
        }
        for (atom, staff) in zip(atoms, staves) {
            for at in atom { placement[at.stave][at.measure][at.event] = staff }
        }

        return Halves(
            above: half(of: voice, keeping: .above, placement: placement, stem: .down),
            below: half(of: voice, keeping: .below, placement: placement, stem: .up))
    }

    // MARK: - Atoms

    /// Where one event of a floating voice is.
    private struct Location {
        let stave: Int
        let measure: Int
        let event: Int
    }

    /// The voice cut into the runs that have to stay together, in playing order.
    ///
    /// A run stays open across a beam (`.start` through `.end`), a tie chain, and anything
    /// that attaches forward — a grace group, a directive anchor.  It runs across bar lines
    /// and across staves where a tie does, which is the only way to keep a tie over a bar
    /// line on one staff.
    private static func atoms(of voice: Voice) -> [[Location]] {
        var atoms: [[Location]] = []
        var beamOpen = false
        var tieOpen = false
        var attachesForward = false

        for (s, stave) in voice.staves.enumerated() {
            for (m, measure) in stave.measures.enumerated() {
                for (e, event) in measure.events.enumerated() {
                    if !(beamOpen || tieOpen || attachesForward) { atoms.append([]) }
                    atoms[atoms.count - 1].append(Location(stave: s, measure: m, event: e))

                    switch event {
                    case .grace, .directiveAnchor:
                        attachesForward = true
                    case .note(let n):
                        attachesForward = false
                        beamOpen = n.beam == .start || n.beam == .middle
                        tieOpen = tiesForward(n.ties)
                    case .chord(let c):
                        attachesForward = false
                        beamOpen = c.beam == .start || c.beam == .middle
                        tieOpen = tiesForward(c.ties) || c.notes.contains { tiesForward($0.ties) }
                    case .tuplet(let t):
                        // A tuplet is one event and so is drawn whole wherever it lands; only
                        // a tie out of its last note can hold the run open past it.
                        attachesForward = false
                        beamOpen = false
                        tieOpen = t.events.last.map(tiesForwardOut(of:)) ?? false
                    case .rest:
                        attachesForward = false
                        beamOpen = false
                        tieOpen = false
                    case .spacer, .tempoChange:
                        // Neither ends a beam: `y` is written *inside* beamed runs to space
                        // them, and an inline `Q:` is not music at all.
                        attachesForward = false
                    }
                }
            }
        }
        return atoms
    }

    private static func tiesForward(_ state: TieState) -> Bool {
        state == .startsTie || state == .continuesTie
    }

    private static func tiesForwardOut(of event: Event) -> Bool {
        switch event {
        case .note(let n):  return tiesForward(n.ties)
        case .chord(let c): return tiesForward(c.ties) || c.notes.contains { tiesForward($0.ties) }
        default:            return false
        }
    }

    /// Every notehead an atom draws, as diatonic indices in written order.
    ///
    /// Grace notes contribute none: an ornament decorates whatever staff its principal note
    /// landed on, and letting a run of high grace notes carry a low note upstairs with them
    /// would be exactly backwards.
    private static func steps(at atom: [Location], in voice: Voice) -> [Int] {
        atom.flatMap { steps(of: voice.staves[$0.stave].measures[$0.measure].events[$0.event]) }
    }

    private static func steps(of event: Event) -> [Int] {
        switch event {
        case .note(let n):   return [FloatingVoiceAssigner.diatonic(of: n.pitch)]
        case .chord(let c):  return c.notes.map { FloatingVoiceAssigner.diatonic(of: $0.pitch) }
        case .tuplet(let t): return t.events.flatMap(steps(of:))
        default:             return []
        }
    }

    // MARK: - Rebuilding

    private static func half(
        of voice: Voice,
        keeping side: FloatingVoiceAssigner.Staff,
        placement: [[[FloatingVoiceAssigner.Staff]]],
        stem: StemDirection
    ) -> Voice {
        let staves = voice.staves.enumerated().map { s, stave in
            Staff(measures: stave.measures.enumerated().map { m, measure in
                self.measure(measure, keeping: side, placement: placement[s][m])
            // Both halves keep the stave's `&` overlays (§7.4) whole.  Nothing in the
            // renderer reads them yet; whatever does will have to split them the same way
            // the measures are split here.
            }, overlays: stave.overlays)
        }
        let properties = VoiceProperties(
            clef: voice.properties.clef,
            transposition: voice.properties.transposition,
            staffProperties: voice.properties.staffProperties,
            name: voice.properties.name,
            subname: voice.properties.subname,
            // The half is the lowest part of the staff above and the highest of the one
            // below, so the opposition #77 draws is the same on both: stems point away from
            // the staff the music came from.  A voice that stated `stem=` keeps its word.
            stemDirection: voice.properties.stemDirection == .auto
                ? stem : voice.properties.stemDirection,
            middleNote: voice.properties.middleNote)
        return Voice(id: voice.id, properties: properties, key: voice.key,
                     unitNoteLength: voice.unitNoteLength, staves: staves,
                     directives: voice.directives, source: voice.source)
    }

    private static func measure(
        _ measure: Measure,
        keeping side: FloatingVoiceAssigner.Staff,
        placement: [FloatingVoiceAssigner.Staff]
    ) -> Measure {
        var events: [Event] = []
        var displaced: Fraction?

        for (index, event) in measure.events.enumerated() {
            guard placement[index] == side else {
                if let duration = sounding(event) {
                    displaced = displaced.map { plus($0, duration) } ?? duration
                }
                continue
            }
            if let duration = displaced {
                events.append(.rest(Rest(kind: .invisible, duration: duration,
                                         decorations: [], source: .emptySourceRange)))
                displaced = nil
            }
            events.append(event)
        }
        // Anything still displaced runs to the bar line, and silence at the end of a bar
        // moves nothing.
        return Measure(openingBar: measure.openingBar, events: events,
                       closingBar: measure.closingBar, endingNumber: measure.endingNumber,
                       source: measure.source, meter: measure.meter)
    }

    // MARK: - Durations

    /// How long `event` sounds, in unit note lengths, or `nil` where it takes no time.
    ///
    /// Summed for tuplets exactly as ``Rational/quarters(of:unitNoteLength:)`` sums them, so
    /// the rest that stands in for a displaced tuplet and the tuplet itself put the following
    /// onset in the same place on both staves.  The voice's `L:` never enters into it: both
    /// halves are the same voice and read every duration against the same unit.
    private static func sounding(_ event: Event) -> Fraction? {
        switch event {
        case .note(let n):  return n.duration
        case .rest(let r):  return r.duration
        case .chord(let c): return c.duration
        case .tuplet(let t):
            let written = t.events.reduce(Fraction(numerator: 0, denominator: 1)) { total, inner in
                sounding(inner).map { plus(total, $0) } ?? total
            }
            return times(written, Fraction(numerator: t.q, denominator: t.p))
        default:
            return nil
        }
    }

    private static func plus(_ lhs: Fraction, _ rhs: Fraction) -> Fraction {
        reduced(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
                lhs.denominator * rhs.denominator)
    }

    private static func times(_ lhs: Fraction, _ rhs: Fraction) -> Fraction {
        reduced(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    private static func reduced(_ numerator: Int, _ denominator: Int) -> Fraction {
        let sign = denominator < 0 ? -1 : 1
        let n = numerator * sign
        let d = denominator * sign
        var a = abs(n), b = d
        while b != 0 { (a, b) = (b, a % b) }
        guard a != 0 else { return Fraction(numerator: 0, denominator: 1) }
        return Fraction(numerator: n / a, denominator: d / a)
    }
}
