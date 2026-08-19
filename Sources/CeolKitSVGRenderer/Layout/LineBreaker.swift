import CeolKitModel

/// Pass 2: groups `SizedMeasure` values into `System` rows.
///
/// Source-forced breaks (`.hard` `ScoreLineBreak`) close the current system immediately,
/// regardless of accumulated width.  The measures between two source-forced breaks — a
/// *stave* — are packed independently of every other stave.
///
/// Packing a stave is two steps.  Greedy first-fit establishes how many systems the stave
/// needs; a balancing pass then redistributes the stave's measures across that same number
/// of systems so none of them is left conspicuously underfull.  Greedy alone turns a 4-bar
/// stave that overflows by a hair into 3 bars plus a lone orphan, which the `Justifier` then
/// stretches across the whole page.  Balancing turns that into 2 + 2.
///
/// A stave is also allowed to overflow the line by ``overflowTolerance`` before it is broken
/// at all: engravers squeeze a line a few percent sooner than they break it, and the
/// `Justifier` compresses whatever the packer hands it that does not fit.
public struct LineBreaker: Sendable {

    /// How far a system may overrun its available width, as a fraction of that width, before
    /// the packer breaks it.  `0.02` lets a line that overflows by up to 2% stay whole and be
    /// compressed by the `Justifier` instead.  Zero restores strict first-fit.
    public let overflowTolerance: Double

    public init(overflowTolerance: Double = 0.02) {
        self.overflowTolerance = max(0, overflowTolerance)
    }

    /// Breaks `measures` into systems.
    ///
    /// - Parameters:
    ///   - measures: Pass 1 output paired with an optional source line-break hint that follows
    ///     each measure. `nil` or `.soft`/`.suppressed` leaves the packer in charge;
    ///     `.hard` forces a system break after that measure.
    ///   - usableWidth: Available horizontal space in points (page width minus left/right margins).
    ///   - firstSystemHeaderWidth: Width consumed by the clef/key/time-sig header on the first
    ///     system. Subtracted from `usableWidth` when packing the first row.
    ///   - laterSystemHeaderWidth: Same for subsequent systems (no time signature).
    ///   - clef: The clef in effect for the voice; propagated to each output `System`.
    ///   - meter: When non-nil, stamped on the first system only (time signatures don't repeat at line breaks).
    public func breakIntoSystems(
        _ measures: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)],
        usableWidth: Double,
        firstSystemHeaderWidth: Double = 0,
        laterSystemHeaderWidth: Double = 0,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil
    ) -> [System] {
        let voice = VoiceLine(measures: measures.map(\.measure), clef: clef,
                              keySignature: keySignature, meter: meter)
        return breakIntoGroups([voice], breaks: measures.map(\.breakAfter),
                               usableWidth: usableWidth,
                               firstSystemHeaderWidth: firstSystemHeaderWidth,
                               laterSystemHeaderWidth: laterSystemHeaderWidth)
            .map { $0.staves[0] }
    }

    /// One voice's contribution to a joint break: its measures and the header material that
    /// travels with them.
    public struct VoiceLine: Sendable {
        public let measures: [SizedMeasure]
        public let clef: ClefSpec
        public let keySignature: KeySignature?
        /// Stamped on the voice's first system only.
        public let meter: Meter?

        public init(measures: [SizedMeasure], clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
                    keySignature: KeySignature? = nil, meter: Meter? = nil) {
            self.measures = measures
            self.clef = clef
            self.keySignature = keySignature
            self.meter = meter
        }
    }

    /// Breaks every voice of a tune at the same measure indices, producing one `SystemGroup`
    /// per system.
    ///
    /// The voices must already agree on measure count and break positions — `VoiceAligner`
    /// pads them into agreement, and warns when it had to.  That is why there is a single
    /// `breaks` array rather than one per voice: a break has to fall at the same measure
    /// index in every voice or the staves desynchronise, so there is only one decision to make.
    ///
    /// Column widths are the `max` across the voices, not each voice's own: a column is only
    /// as narrow as its widest staff can be drawn.
    ///
    /// - Parameters:
    ///   - voices: One entry per voice, in `V:` declaration order. Every `measures` array
    ///     has the same count, equal to `breaks.count`.
    ///   - breaks: The source line-break hint following each measure column.
    ///   - firstSystemHeaderWidth: Header width on the tune's first system — already the
    ///     `max` across voices, since the group's staves must start at a common x.
    ///   - laterSystemHeaderWidth: Same for every later system (no time signature).
    ///   - grouping: The staff plan's spans and bar-line joins, stamped on every group.
    ///     Only the plan governing the tune's first stave applies, so every system of a
    ///     tune is grouped the same way and the breaker has nothing to decide here.
    public func breakIntoGroups(
        _ voices: [VoiceLine],
        breaks: [ScoreLineBreak?],
        usableWidth: Double,
        firstSystemHeaderWidth: Double = 0,
        laterSystemHeaderWidth: Double = 0,
        grouping: StaffGrouping? = nil
    ) -> [SystemGroup] {
        guard let first = voices.first, !first.measures.isEmpty else { return [] }

        // A column is as wide as its widest voice needs it to be.
        let columnWidths = (0..<first.measures.count).map { column in
            voices.reduce(0.0) { max($0, $1.measures[column].naturalWidth) }
        }

        var groups: [SystemGroup] = []
        for stave in staves(columnCount: columnWidths.count, breaks: breaks) {
            // Header width — and therefore the space left for music — differs between the
            // very first system of the tune and every later one.
            let firstSystemIndex = groups.count
            let available: (Int) -> Double = { indexWithinStave in
                usableWidth - (firstSystemIndex + indexWithinStave == 0
                               ? firstSystemHeaderWidth
                               : laterSystemHeaderWidth)
            }

            let ranges = pack(Array(columnWidths[stave.columns]), available: available)
                .map { $0.offset(by: stave.columns.lowerBound) }
            for (i, range) in ranges.enumerated() {
                let isLastOfStave = i == ranges.count - 1
                let isFirstOfTune = groups.isEmpty
                groups.append(SystemGroup(staves: voices.map { voice in
                    System(
                        measures: Array(voice.measures[range]),
                        isLastSystem: false,
                        // Only the system that ends on the source break inherited it.
                        sourceForced: stave.endsAtSourceBreak && isLastOfStave,
                        staveWasSplit: ranges.count > 1,
                        clef: voice.clef,
                        keySignature: voice.keySignature,
                        meter: isFirstOfTune ? voice.meter : nil
                    )
                }, grouping: grouping))
            }
        }

        // Mark the trailing system.
        if let last = groups.popLast() {
            groups.append(SystemGroup(staves: last.staves.map { staff in
                System(measures: staff.measures, isLastSystem: true,
                       sourceForced: staff.sourceForced, staveWasSplit: staff.staveWasSplit,
                       clef: staff.clef, keySignature: staff.keySignature, meter: staff.meter)
            }, grouping: last.grouping))
        }

        return groups
    }

    // MARK: - Staves

    private struct Stave {
        /// The measure columns this stave covers.
        let columns: Range<Int>
        /// `true` when the stave closes on a `.hard` source break rather than on the end of input.
        let endsAtSourceBreak: Bool
    }

    /// Splits `0..<columnCount` at every `.hard` break.  A trailing run with no break after
    /// it is a stave too — it just ends at the end of the tune.
    private func staves(columnCount: Int, breaks: [ScoreLineBreak?]) -> [Stave] {
        var result: [Stave] = []
        var start = 0
        for column in 0..<columnCount where column < breaks.count && breaks[column] == .hard {
            result.append(Stave(columns: start..<(column + 1), endsAtSourceBreak: true))
            start = column + 1
        }
        if start < columnCount {
            result.append(Stave(columns: start..<columnCount, endsAtSourceBreak: false))
        }
        return result
    }

    // MARK: - Packing

    /// Splits one stave into system-sized runs of columns, as ranges into `widths`.
    ///
    /// `available(i)` gives the width left for music on the `i`-th system of this stave.
    private func pack(_ widths: [Double], available: (Int) -> Double) -> [Range<Int>] {
        guard !widths.isEmpty else { return [] }
        let greedy = greedyPack(widths, available: available)
        // A stave that fits on one system has nothing to rebalance.
        guard greedy.count > 1 else { return greedy }
        return balance(widths, systemCount: greedy.count, available: available) ?? greedy
    }

    /// First-fit packing.  Establishes the minimum number of systems the stave needs; the
    /// balancing pass keeps that number and only moves columns between the systems.
    private func greedyPack(_ widths: [Double], available: (Int) -> Double) -> [Range<Int>] {
        var groups: [Range<Int>] = []
        var start = 0
        var bucketWidth: Double = 0

        for (i, width) in widths.enumerated() {
            let limit = capacity(available(groups.count))
            if i > start && bucketWidth + width > limit {
                groups.append(start..<i)
                start = i
                bucketWidth = 0
            }
            bucketWidth += width
        }
        if start < widths.count { groups.append(start..<widths.count) }
        return groups
    }

    /// The widest a system may get before it has to be broken.
    private func capacity(_ available: Double) -> Double {
        available * (1 + overflowTolerance)
    }

    /// Redistributes the columns over exactly `systemCount` systems, minimising the total
    /// squared relative slack.
    ///
    /// Measure counts per stave are small (a source line is rarely more than a dozen bars),
    /// so an exact O(systemCount · n²) dynamic program is cheaper than reasoning about when a
    /// heuristic would misfire.  Returns `nil` if no assignment respects the width limits,
    /// which cannot happen for a `systemCount` that greedy first-fit already achieved.
    private func balance(_ widths: [Double], systemCount: Int,
                         available: (Int) -> Double) -> [Range<Int>]? {
        let n = widths.count
        guard systemCount > 1, systemCount <= n else { return nil }

        // prefix[i] = summed natural width of widths[0..<i]
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + widths[i] }

        // cost[s][i]: best badness for packing measures[i...] into exactly `s` systems.
        // choice[s][i]: where the system starting at `i` ends in that solution.
        var cost = [[Double]](repeating: [Double](repeating: .infinity, count: n + 1),
                              count: systemCount + 1)
        var choice = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: systemCount + 1)
        cost[0][n] = 0

        for s in 1...systemCount {
            // The system being filled is the (systemCount - s)-th of this stave.
            let width = available(systemCount - s)
            let limit = capacity(width)
            // Leave room for the s-1 systems that follow: each needs at least one measure.
            let lastStart = n - s
            guard lastStart >= 0 else { continue }
            for i in stride(from: lastStart, through: 0, by: -1) {
                var best = Double.infinity
                var bestEnd = 0
                for j in (i + 1)...(n - s + 1) {
                    let groupWidth = prefix[j] - prefix[i]
                    // A single measure wider than the line has nowhere else to go; anything
                    // else that overruns the limit must be broken.
                    if groupWidth > limit && j - i > 1 { break }
                    guard cost[s - 1][j] < .infinity else { continue }
                    let total = badness(groupWidth: groupWidth, available: width) + cost[s - 1][j]
                    // `<=` breaks ties towards the fuller earlier system, matching first-fit.
                    if total <= best {
                        best = total
                        bestEnd = j
                    }
                }
                cost[s][i] = best
                choice[s][i] = bestEnd
            }
        }

        guard cost[systemCount][0] < .infinity else { return nil }

        var groups: [Range<Int>] = []
        var start = 0
        for s in stride(from: systemCount, through: 1, by: -1) {
            let end = choice[s][start]
            groups.append(start..<end)
            start = end
        }
        return groups
    }

    /// Squared relative slack.  Relative rather than absolute so systems with different
    /// header widths are compared on equal terms, and squared so one badly underfull system
    /// costs more than the same total slack spread evenly.  Overfull systems are penalised
    /// symmetrically.
    private func badness(groupWidth: Double, available: Double) -> Double {
        guard available > 0 else { return 0 }
        let slack = (available - groupWidth) / available
        return slack * slack
    }
}

private extension Range where Bound == Int {
    func offset(by delta: Int) -> Range<Int> { (lowerBound + delta)..<(upperBound + delta) }
}
