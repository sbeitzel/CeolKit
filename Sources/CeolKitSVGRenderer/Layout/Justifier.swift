/// Pass 3: distributes horizontal slack across measures so each non-last system
/// fills the full usable line width.
///
/// Two things stop that from being unconditional.  A system whose music overruns the line —
/// which the `LineBreaker` now allows within its overflow tolerance — is compressed to fit
/// instead, last system or not.  And a system the breaker itself created by splitting an
/// over-long stave is stretched no further than ``maxStretch``, so an unavoidably near-empty
/// system is left short rather than smeared across the page.
public struct Justifier: Sendable {

    /// The most a system whose width the line breaker chose — one from a stave it had to
    /// split — may be stretched, as a multiple of its natural width.  Past this the system is
    /// left short and aligned to the left margin rather than pulled across the page.
    ///
    /// Deliberately generous.  Filling the line is the normal thing to do with the halves of
    /// a split stave, and a stave that is a hair over one line balances into two systems that
    /// each need ~2× to fill, so anything near 2 would leave ordinary music ragged.  The cap
    /// exists for the case balancing cannot reach — a stave of one long measure and one short
    /// one, where the short system would otherwise be smeared across the whole page.  At `3`
    /// it only engages below a third of the line, and a system that empty *should* look short.
    ///
    /// A system the *source* asked for (a line the writer chose to end early) is never
    /// capped: stretching those to the full line is standard practice, and asked for.
    public let maxStretch: Double

    public init(maxStretch: Double = 3.0) {
        self.maxStretch = max(1, maxStretch)
    }

    /// Justifies `systems` so each fills the available measure width.
    ///
    /// - Parameters:
    ///   - systems: Pass 2 output.
    ///   - usableWidth: Full available horizontal space (page width minus margins).
    ///   - justifyLastSystem: When `true`, the last system is also stretched to fill the line.
    ///   - systemHeaderWidths: Per-system width consumed by clef/key/time-sig headers.
    ///     The target width for system `i` is `usableWidth - systemHeaderWidths[i]`.
    ///     Defaults to zero for any system not covered by the array.
    public func justify(
        _ systems: [System],
        usableWidth: Double,
        justifyLastSystem: Bool,
        systemHeaderWidths: [Double] = []
    ) -> [JustifiedSystem] {
        justifyGroups(systems.map { SystemGroup(staves: [$0]) },
                      usableWidth: usableWidth,
                      justifyLastSystem: justifyLastSystem,
                      systemHeaderWidths: systemHeaderWidths)
            .map { $0.staves[0] }
    }

    /// Justifies `groups`, giving every staff of a group the same measure x-positions.
    ///
    /// A column's final width is derived once, from the widest staff's natural width for
    /// that column, and handed to every staff in the group.  That is what makes the bar
    /// lines line up vertically: a staff whose measure is narrower than the column simply
    /// gets more slack distributed inside it.
    ///
    /// - Parameters:
    ///   - groups: Pass 2 output.
    ///   - usableWidth: Full available horizontal space (page width minus margins).
    ///   - justifyLastSystem: When `true`, the last system is also stretched to fill the line.
    ///   - systemHeaderWidths: Per-system width consumed by clef/key/time-sig headers —
    ///     already the `max` across the group's voices, since its staves start at a common x.
    /// Named rather than overloaded on the element type: `justify([])` would otherwise be
    /// ambiguous, which is a trap for a call site that has nothing to justify.
    public func justifyGroups(
        _ groups: [SystemGroup],
        usableWidth: Double,
        justifyLastSystem: Bool,
        systemHeaderWidths: [Double] = []
    ) -> [JustifiedSystemGroup] {
        groups.enumerated().map { i, group in
            let headerWidth = i < systemHeaderWidths.count ? systemHeaderWidths[i] : 0
            let targetWidth = usableWidth - headerWidth
            let shouldStretch = !group.isLastSystem || justifyLastSystem
            return justify(group, targetWidth: targetWidth, stretch: shouldStretch,
                           capStretch: group.staveWasSplit)
        }
    }

    // MARK: - Private

    private func justify(_ group: SystemGroup, targetWidth: Double, stretch: Bool,
                         capStretch: Bool) -> JustifiedSystemGroup {
        // A column is as wide as its widest staff needs; every staff is then drawn to that.
        let columnWidths = (0..<group.columnCount).map { column in
            group.staves.reduce(0.0) { max($0, $1.measures[column].naturalWidth) }
        }
        let naturalTotal = columnWidths.reduce(0, +)
        let finalTotal = resolvedWidth(naturalTotal: naturalTotal, targetWidth: targetWidth,
                                       stretch: stretch, capStretch: capStretch)

        let finalWidths: [Double]
        if naturalTotal > 0 && finalTotal != naturalTotal {
            let slack = finalTotal - naturalTotal
            finalWidths = columnWidths.map { $0 + slack * ($0 / naturalTotal) }
        } else {
            // Nothing to redistribute: keep natural widths (left-aligned).
            finalWidths = columnWidths
        }

        let staves = group.staves.map { staff -> JustifiedSystem in
            let measures = staff.measures.enumerated().map { column, sized -> JustifiedMeasure in
                let finalWidth = finalWidths[column]
                guard finalWidth != sized.naturalWidth else {
                    return JustifiedMeasure(source: sized, finalWidth: finalWidth,
                                            eventOffsets: sized.eventOffsets)
                }
                let offsets = stretchOffsets(sized.eventOffsets,
                                             naturalWidth: sized.naturalWidth,
                                             finalWidth: finalWidth,
                                             graceIndices: sized.graceEventIndices)
                return JustifiedMeasure(source: sized, finalWidth: finalWidth, eventOffsets: offsets)
            }
            return JustifiedSystem(measures: measures, isLastSystem: staff.isLastSystem,
                                   sourceForced: staff.sourceForced, clef: staff.clef,
                                   keySignature: staff.keySignature, meter: staff.meter,
                                   voiceLabel: staff.voiceLabel, stemDirection: staff.stemDirection)
        }
        return JustifiedSystemGroup(staves: staves, grouping: group.grouping)
    }

    /// The width the system's music is laid out to.
    ///
    /// A system that overruns is squeezed back onto the line whether or not it would
    /// otherwise be stretched — music must not cross the right margin, and the line breaker
    /// now hands over systems that deliberately overrun by a percent or two.
    private func resolvedWidth(naturalTotal: Double, targetWidth: Double,
                               stretch: Bool, capStretch: Bool) -> Double {
        if naturalTotal > targetWidth { return targetWidth }
        guard stretch else { return naturalTotal }
        guard capStretch else { return targetWidth }
        return min(targetWidth, naturalTotal * maxStretch)
    }

    /// Stretches `offsets` from `naturalWidth` to `finalWidth` while keeping the gap within
    /// each grace+note pair fixed.  All horizontal slack goes to elastic (note-to-note) spacings.
    ///
    /// The elastic scale factor is derived from the *elastic* portion of the measure width:
    /// `naturalWidth` minus the leading margin (`base`) and all fixed grace-to-note gaps
    /// (`fixedTotal`).  Grace events (identified by `graceIndices`) stay fixed relative to
    /// the note they precede; every other event is scaled proportionally.
    ///
    /// How much fixed width lies to an event's left is asked of the *offsets*, not of the
    /// array order.  On a single-voice measure the two agree, because offsets only ever
    /// increase.  A shared staff (§11.1 `( … )`) is where they part: its events are ordered
    /// voice by voice within each onset so that no grace group is separated from its note,
    /// which means the array steps backwards every time a new voice starts its run.
    private func stretchOffsets(_ offsets: [Double], naturalWidth: Double, finalWidth: Double,
                                 graceIndices: Set<Int>) -> [Double] {
        guard !offsets.isEmpty else { return offsets }
        let base = offsets[0]

        // One entry per grace+note pair: where its note sits, and the incompressible gap
        // between the two.
        let pairs: [(note: Int, x: Double, gap: Double)] = graceIndices.sorted().compactMap {
            guard $0 + 1 < offsets.count else { return nil }
            return (note: $0 + 1, x: offsets[$0 + 1], gap: offsets[$0 + 1] - offsets[$0])
        }
        let fixedTotal = pairs.reduce(0.0) { $0 + $1.gap }

        let elasticNatural = naturalWidth - base - fixedTotal
        guard elasticNatural > 0 else { return offsets }
        // Compression never runs the elastic spacings past zero: the fixed parts of the
        // measure are incompressible, so there is nothing sane to do below that point.
        let elasticScale = max(0, (finalWidth - base - fixedTotal) / elasticNatural)

        /// The fixed width of every grace pair that finishes to the left of event `i`.
        /// Ties — a zero-width column, or a second voice sounding at the same x — are broken
        /// by array position, which is what the single-voice walk this replaces did.
        func fixedLeftOf(_ i: Int) -> Double {
            pairs.reduce(0.0) { sum, pair in
                guard pair.note != i, pair.note - 1 != i else { return sum }
                let isLeft = pair.x < offsets[i] || (pair.x == offsets[i] && pair.note < i)
                return isLeft ? sum + pair.gap : sum
            }
        }

        var result = [Double](repeating: 0, count: offsets.count)
        for i in 0..<offsets.count {
            if i > 0 && graceIndices.contains(i - 1) {
                // Pair-follower: preserve the fixed gap from the preceding grace event.
                result[i] = result[i - 1] + (offsets[i] - offsets[i - 1])
            } else {
                // Elastic event: scale its position relative to the base.
                let fixed = fixedLeftOf(i)
                result[i] = base + fixed + (offsets[i] - base - fixed) * elasticScale
            }
        }
        return result
    }
}
