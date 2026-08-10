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
        var systems: [System] = []

        for stave in staves(of: measures) {
            // Header width — and therefore the space left for music — differs between the
            // very first system of the voice and every later one.
            let firstSystemIndex = systems.count
            let available: (Int) -> Double = { indexWithinStave in
                usableWidth - (firstSystemIndex + indexWithinStave == 0
                               ? firstSystemHeaderWidth
                               : laterSystemHeaderWidth)
            }

            let groups = pack(stave.measures, available: available)
            for (i, group) in groups.enumerated() {
                let isLastOfStave = i == groups.count - 1
                systems.append(System(
                    measures: group,
                    isLastSystem: false,
                    // Only the group that ends on the source break inherited it.
                    sourceForced: stave.endsAtSourceBreak && isLastOfStave,
                    staveWasSplit: groups.count > 1,
                    clef: clef,
                    keySignature: keySignature,
                    meter: systems.isEmpty ? meter : nil
                ))
            }
        }

        // Mark the trailing system.
        if !systems.isEmpty {
            let last = systems.removeLast()
            systems.append(System(measures: last.measures, isLastSystem: true,
                                  sourceForced: last.sourceForced,
                                  staveWasSplit: last.staveWasSplit, clef: clef,
                                  keySignature: keySignature, meter: last.meter))
        }

        return systems
    }

    // MARK: - Staves

    private struct Stave {
        let measures: [SizedMeasure]
        /// `true` when the stave closes on a `.hard` source break rather than on the end of input.
        let endsAtSourceBreak: Bool
    }

    /// Splits the input at every `.hard` break.  A trailing run with no break after it is a
    /// stave too — it just ends at the end of the voice.
    private func staves(
        of measures: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)]
    ) -> [Stave] {
        var result: [Stave] = []
        var current: [SizedMeasure] = []
        for (sized, breakAfter) in measures {
            current.append(sized)
            if breakAfter == .hard {
                result.append(Stave(measures: current, endsAtSourceBreak: true))
                current = []
            }
        }
        if !current.isEmpty {
            result.append(Stave(measures: current, endsAtSourceBreak: false))
        }
        return result
    }

    // MARK: - Packing

    /// Splits one stave into system-sized groups.
    ///
    /// `available(i)` gives the width left for music on the `i`-th system of this stave.
    private func pack(_ measures: [SizedMeasure], available: (Int) -> Double) -> [[SizedMeasure]] {
        guard !measures.isEmpty else { return [] }
        let greedy = greedyPack(measures, available: available)
        // A stave that fits on one system has nothing to rebalance.
        guard greedy.count > 1 else { return greedy }
        return balance(measures, systemCount: greedy.count, available: available) ?? greedy
    }

    /// First-fit packing.  Establishes the minimum number of systems the stave needs; the
    /// balancing pass keeps that number and only moves measures between the groups.
    private func greedyPack(_ measures: [SizedMeasure], available: (Int) -> Double) -> [[SizedMeasure]] {
        var groups: [[SizedMeasure]] = []
        var bucket: [SizedMeasure] = []
        var bucketWidth: Double = 0

        for sized in measures {
            let limit = capacity(available(groups.count))
            if !bucket.isEmpty && bucketWidth + sized.naturalWidth > limit {
                groups.append(bucket)
                bucket = []
                bucketWidth = 0
            }
            bucket.append(sized)
            bucketWidth += sized.naturalWidth
        }
        if !bucket.isEmpty { groups.append(bucket) }
        return groups
    }

    /// The widest a system may get before it has to be broken.
    private func capacity(_ available: Double) -> Double {
        available * (1 + overflowTolerance)
    }

    /// Redistributes `measures` over exactly `systemCount` systems, minimising the total
    /// squared relative slack.
    ///
    /// Measure counts per stave are small (a source line is rarely more than a dozen bars),
    /// so an exact O(systemCount · n²) dynamic program is cheaper than reasoning about when a
    /// heuristic would misfire.  Returns `nil` if no assignment respects the width limits,
    /// which cannot happen for a `systemCount` that greedy first-fit already achieved.
    private func balance(_ measures: [SizedMeasure], systemCount: Int,
                         available: (Int) -> Double) -> [[SizedMeasure]]? {
        let n = measures.count
        guard systemCount > 1, systemCount <= n else { return nil }

        // prefix[i] = summed natural width of measures[0..<i]
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + measures[i].naturalWidth }

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

        var groups: [[SizedMeasure]] = []
        var start = 0
        for s in stride(from: systemCount, through: 1, by: -1) {
            let end = choice[s][start]
            groups.append(Array(measures[start..<end]))
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
