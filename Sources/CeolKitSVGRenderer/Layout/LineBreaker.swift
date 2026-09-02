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
        /// The same columns, sized as they are drawn when one *opens* a system: a `K:` landing
        /// on such a column is engraved in the staff head rather than at the head of the bar,
        /// so the bar reserves no space for it (#134).  Only the columns carrying a change
        /// differ from ``measures``; empty means none do.
        public let systemStartMeasures: [SizedMeasure]
        public let clef: ClefSpec
        /// The key the voice opens in, and the signature every staff head draws where
        /// ``columnKeys`` says nothing more specific.
        public let keySignature: KeySignature?
        /// The key in force *from* each column on — the tune's or voice's `K:` until a body
        /// `K:` moves it, and the new key from the column that one lands on (#134).  Parallel
        /// to ``measures``; empty means the voice never changes key and every system's head
        /// draws ``keySignature``.
        public let columnKeys: [KeySignature?]
        /// Stamped on the voice's first system only.
        public let meter: Meter?
        /// What the voice is called on the first system it appears on — its `V:` `name=`.
        public let firstSystemLabel: String?
        /// What it is called on every system after that — its `sname=`.  Nil where the voice
        /// has none, and deliberately not defaulted to ``firstSystemLabel``: a voice named
        /// once and never again is what the spec asks for and what abcm2ps prints.
        public let laterSystemLabel: String?
        /// The `V:` `stem=` of every voice drawn on this staff, in staff order — one entry
        /// each, so a shared staff (§11.1 `( … )`) has one per tenant.  Stamped on every
        /// system the staff appears on: unlike the label, `stem=` does not change between
        /// the first system and the rest.
        public let voiceStemDirections: [StemDirection]

        public init(measures: [SizedMeasure], clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
                    keySignature: KeySignature? = nil, meter: Meter? = nil,
                    firstSystemLabel: String? = nil, laterSystemLabel: String? = nil,
                    voiceStemDirections: [StemDirection] = [],
                    systemStartMeasures: [SizedMeasure] = [],
                    columnKeys: [KeySignature?] = []) {
            self.measures = measures
            // A caller with nothing to say about key changes gets the plain columns back for
            // both roles, so everything below can index one array without testing the other.
            self.systemStartMeasures = systemStartMeasures.count == measures.count
                ? systemStartMeasures : measures
            self.columnKeys = columnKeys.count == measures.count
                ? columnKeys : Array(repeating: keySignature, count: measures.count)
            self.clef = clef
            self.keySignature = keySignature
            self.meter = meter
            self.firstSystemLabel = firstSystemLabel
            self.laterSystemLabel = laterSystemLabel
            self.voiceStemDirections = voiceStemDirections
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
    ///     One call covers one plan region (see `PlanRegions`), so a single grouping governs
    ///     everything the breaker is handed and it has nothing to decide here.
    ///   - headerWidth: The header width of a system that is the `systemIndex`-th of this call
    ///     and opens on measure column `startColumn`.  Supersedes the two flat widths above,
    ///     which cannot express a staff head whose key signature depends on where the system
    ///     starts (#134); `nil` falls back to them.
    public func breakIntoGroups(
        _ voices: [VoiceLine],
        breaks: [ScoreLineBreak?],
        usableWidth: Double,
        firstSystemHeaderWidth: Double = 0,
        laterSystemHeaderWidth: Double = 0,
        grouping: StaffGrouping? = nil,
        headerWidth: ((_ systemIndex: Int, _ startColumn: Int) -> Double)? = nil
    ) -> [SystemGroup] {
        guard let first = voices.first, !first.measures.isEmpty else { return [] }

        // A column is as wide as its widest voice needs it to be.
        let columnWidths = (0..<first.measures.count).map { column in
            voices.reduce(0.0) { max($0, $1.measures[column].naturalWidth) }
        }
        // What that same column costs when it *opens* a system and its key change moves up
        // into the staff head.  Refunded to the line rather than subtracted from the column,
        // which is the same arithmetic and leaves the packer's prefix sums alone.
        let startRefunds = (0..<first.measures.count).map { column in
            columnWidths[column] - voices.reduce(0.0) {
                max($0, $1.systemStartMeasures[column].naturalWidth)
            }
        }
        let headerW = headerWidth ?? { systemIndex, _ in
            systemIndex == 0 ? firstSystemHeaderWidth : laterSystemHeaderWidth
        }

        var groups: [SystemGroup] = []
        for stave in staves(columnCount: columnWidths.count, breaks: breaks) {
            // Header width — and therefore the space left for music — is the header of the
            // system that starts at this column, which differs between the tune's first
            // system and every later one and again wherever a `K:` lands.
            let firstSystemIndex = groups.count
            let offset = stave.columns.lowerBound
            let available: (Int, Int) -> Double = { indexWithinStave, startWithinStave in
                let column = offset + startWithinStave
                return usableWidth - headerW(firstSystemIndex + indexWithinStave, column)
                    + startRefunds[column]
            }

            let ranges = pack(Array(columnWidths[stave.columns]), available: available)
                .map { $0.offset(by: offset) }
            for (i, range) in ranges.enumerated() {
                let isLastOfStave = i == ranges.count - 1
                let isFirstOfTune = groups.isEmpty
                let start = range.lowerBound
                groups.append(SystemGroup(staves: voices.map { voice in
                    System(
                        // The opening column is the one drawn without its in-bar key change:
                        // a system that starts on a `K:` engraves it in the staff head.
                        measures: [voice.systemStartMeasures[start]]
                            + voice.measures[(start + 1)..<range.upperBound],
                        isLastSystem: false,
                        // Only the system that ends on the source break inherited it.
                        sourceForced: stave.endsAtSourceBreak && isLastOfStave,
                        staveWasSplit: ranges.count > 1,
                        clef: voice.clef,
                        keySignature: voice.columnKeys[start],
                        meter: isFirstOfTune ? voice.meter : nil,
                        voiceLabel: isFirstOfTune ? voice.firstSystemLabel : voice.laterSystemLabel,
                        voiceStemDirections: voice.voiceStemDirections,
                        headerKeyChange: voice.measures[start].keyChange
                    )
                }, grouping: grouping))
            }
        }

        // Mark the trailing system.
        if let last = groups.popLast() {
            groups.append(SystemGroup(staves: last.staves.map { staff in
                System(measures: staff.measures, isLastSystem: true,
                       sourceForced: staff.sourceForced, staveWasSplit: staff.staveWasSplit,
                       clef: staff.clef, keySignature: staff.keySignature, meter: staff.meter,
                       voiceLabel: staff.voiceLabel,
                       voiceStemDirections: staff.voiceStemDirections,
                       headerKeyChange: staff.headerKeyChange)
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
    /// `available(i, c)` gives the width left for music on the `i`-th system of this stave
    /// when it opens on column `c` of `widths` — the staff head it has to draw, and therefore
    /// the room left over, depends on where it starts (#134).
    private func pack(_ widths: [Double], available: (Int, Int) -> Double) -> [Range<Int>] {
        guard !widths.isEmpty else { return [] }
        let greedy = greedyPack(widths, available: available)
        // A stave that fits on one system has nothing to rebalance.
        guard greedy.count > 1 else { return greedy }
        return balance(widths, systemCount: greedy.count, available: available) ?? greedy
    }

    /// First-fit packing.  Establishes the minimum number of systems the stave needs; the
    /// balancing pass keeps that number and only moves columns between the systems.
    private func greedyPack(_ widths: [Double], available: (Int, Int) -> Double) -> [Range<Int>] {
        var groups: [Range<Int>] = []
        var start = 0
        var bucketWidth: Double = 0

        for (i, width) in widths.enumerated() {
            let limit = capacity(available(groups.count, start))
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
                         available: (Int, Int) -> Double) -> [Range<Int>]? {
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
            // Leave room for the s-1 systems that follow: each needs at least one measure.
            let lastStart = n - s
            guard lastStart >= 0 else { continue }
            for i in stride(from: lastStart, through: 0, by: -1) {
                // The system being filled is the (systemCount - s)-th of this stave and it
                // opens on column `i`, which is what decides the head it draws.
                let width = available(systemCount - s, i)
                let limit = capacity(width)
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
