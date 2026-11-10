import CeolKitModel

/// Which staff of a score draws the marks that stand at a bar line (issue #264), so that a
/// bar line running down from the staff above never cuts through them.
///
/// Gould (*Behind Bars*, "Da Capo and Dal Segno layouts", p. 240; and on the comma and
/// caesura): "The signs 𝄋 and 𝄌 go above the stave (or top stave of a system), centred over
/// the barline", and "In a score, the comma, caesura and pause over a barline should appear
/// at the top of each instrumental section only (so as not to be intersected by a barline).
/// When not over a barline, place the symbols above every stave."
///
/// So, bar by bar:
/// - the segno and coda written on a bar line of any staff are drawn once, over the
///   system's top staff;
/// - the breath mark, caesura, phrase marks and fermata *over a bar line* — written on it,
///   or a pause mark on the last note before it — are drawn once per section, over the
///   section's top staff.  A section is a run of staves whose bar lines are joined
///   (`|` in `%%score`; with no plan every staff of the system is joined);
/// - everything else stays on the staff it was written on.
///
/// A system of one staff is its own section and its own top: nothing moves.
struct BarMarkSections {

    /// The decorations each staff's bar lines carry as drawn, by measure index.
    private let closing: [[[Decoration]]]
    private let opening: [[[Decoration]]]
    /// Per staff, whether the pause marks on the last note before each bar line are its own
    /// to draw: `false` on a staff below the top of its section.
    let drawsPausesAtBarLine: [Bool]

    /// The marks this plan moves between staves.
    static func isSystemSign(_ decoration: Decoration) -> Bool {
        decoration == .segno || decoration == .coda
    }

    static func isOverBarLine(_ decoration: Decoration) -> Bool {
        decoration.isPause || decoration == .fermata
    }

    /// - Parameters:
    ///   - staves: per staff, its bars as written.
    ///   - joinsBelow: whether staff `i`'s bar lines run on into staff `i + 1`.
    init(staves: [[(measure: Measure, voices: [Int])]], joinsBelow: (Int) -> Bool) {
        let count = staves.count
        var sectionTop = Array(0..<count)
        for i in 1..<max(count, 1) where joinsBelow(i - 1) {
            sectionTop[i] = sectionTop[i - 1]
        }
        drawsPausesAtBarLine = (0..<count).map { sectionTop[$0] == $0 }

        /// `bars[i][m]` as staff `i` draws it.  `extra[i][m]` are the pause marks staff
        /// `i` draws in front of that bar line from its own last note.
        func gather(_ bars: [[[Decoration]]], extra: [[[Decoration]]]) -> [[[Decoration]]] {
            func at(_ table: [[[Decoration]]], _ i: Int, _ m: Int) -> [Decoration] {
                table.indices.contains(i) && table[i].indices.contains(m) ? table[i][m] : []
            }
            var drawn = bars
            for (i, staff) in bars.enumerated() {
                let isSectionTop = sectionTop[i] == i
                for m in staff.indices {
                    var own = staff[m].filter {
                        (!Self.isSystemSign($0) || i == 0)
                            && (!Self.isOverBarLine($0) || isSectionTop)
                    }
                    func add(_ decoration: Decoration) {
                        guard !own.contains(decoration),
                              !at(extra, i, m).contains(decoration) else { return }
                        own.append(decoration)
                    }
                    for j in bars.indices where j != i {
                        if i == 0 {
                            at(bars, j, m).filter(Self.isSystemSign).forEach(add)
                        }
                        if isSectionTop, sectionTop[j] == i {
                            (at(bars, j, m) + at(extra, j, m)).filter(Self.isOverBarLine)
                                .forEach(add)
                        }
                    }
                    drawn[i][m] = own
                }
            }
            return drawn
        }

        let closingBars = staves.map { $0.map(\.measure.closingBar.decorations) }
        let openingBars = staves.map { $0.map { $0.measure.openingBar?.decorations ?? [] } }
        // The pause marks on the last note of each part before the closing bar line.
        let lastNotePauses = staves.map { $0.map(Self.pausesBeforeClosingBar) }
        closing = gather(closingBars, extra: lastNotePauses)
        opening = gather(openingBars, extra: staves.map { $0.map { _ in [] } })
    }

    /// What staff `staff`'s closing bar line of measure `measure` draws.
    func closingDecorations(staff: Int, measure: Int) -> [Decoration] {
        guard closing.indices.contains(staff), closing[staff].indices.contains(measure) else {
            return []
        }
        return closing[staff][measure]
    }

    /// What staff `staff`'s opening bar line of measure `measure` draws.
    func openingDecorations(staff: Int, measure: Int) -> [Decoration] {
        guard opening.indices.contains(staff), opening[staff].indices.contains(measure) else {
            return []
        }
        return opening[staff][measure]
    }

    /// The pause marks on the last note, chord or rest of each part of `bar`, which stand
    /// just before its closing bar line.
    private static func pausesBeforeClosingBar(_ bar: (measure: Measure, voices: [Int])) -> [Decoration] {
        var last: [Int: [Decoration]] = [:]
        for (index, event) in bar.measure.events.enumerated() {
            guard let decorations = musicDecorations(event) else { continue }
            let voice = index < bar.voices.count ? bar.voices[index] : 0
            last[voice] = decorations
        }
        var pauses: [Decoration] = []
        for voice in last.keys.sorted() {
            for decoration in last[voice] ?? [] where decoration.isPause
                && !pauses.contains(decoration) {
                pauses.append(decoration)
            }
        }
        return pauses
    }

    /// The decorations of a note, chord or rest — of a tuplet, its last — or `nil` for an
    /// event that is not music.
    private static func musicDecorations(_ event: Event) -> [Decoration]? {
        switch event {
        case .note(let n):  return n.decorations
        case .chord(let c): return c.decorations + c.notes.flatMap(\.decorations)
        case .rest(let r):  return r.decorations
        case .tuplet(let t): return t.events.last.flatMap(musicDecorations)
        default:            return nil
        }
    }
}
