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
        systems.enumerated().map { i, system in
            let headerWidth = i < systemHeaderWidths.count ? systemHeaderWidths[i] : 0
            let targetWidth = usableWidth - headerWidth
            let shouldStretch = !system.isLastSystem || justifyLastSystem
            return justify(system, targetWidth: targetWidth, stretch: shouldStretch,
                           capStretch: system.staveWasSplit)
        }
    }

    // MARK: - Private

    private func justify(_ system: System, targetWidth: Double, stretch: Bool,
                         capStretch: Bool) -> JustifiedSystem {
        let naturalTotal = system.measures.reduce(0.0) { $0 + $1.naturalWidth }
        let finalTotal = resolvedWidth(naturalTotal: naturalTotal, targetWidth: targetWidth,
                                       stretch: stretch, capStretch: capStretch)

        guard naturalTotal > 0, finalTotal != naturalTotal else {
            // Nothing to redistribute: keep natural widths (left-aligned).
            let measures = system.measures.map { sized in
                JustifiedMeasure(source: sized, finalWidth: sized.naturalWidth, eventOffsets: sized.eventOffsets)
            }
            return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                                   sourceForced: system.sourceForced, clef: system.clef,
                                   keySignature: system.keySignature, meter: system.meter)
        }

        let slack = finalTotal - naturalTotal
        let measures = system.measures.map { sized -> JustifiedMeasure in
            let share = slack * (sized.naturalWidth / naturalTotal)
            let finalWidth = sized.naturalWidth + share
            let offsets = stretchOffsets(sized.eventOffsets,
                                         naturalWidth: sized.naturalWidth,
                                         finalWidth: finalWidth,
                                         graceIndices: sized.graceEventIndices)
            return JustifiedMeasure(source: sized, finalWidth: finalWidth, eventOffsets: offsets)
        }
        return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                               sourceForced: system.sourceForced, clef: system.clef,
                               keySignature: system.keySignature, meter: system.meter)
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
    private func stretchOffsets(_ offsets: [Double], naturalWidth: Double, finalWidth: Double,
                                 graceIndices: Set<Int>) -> [Double] {
        guard !offsets.isEmpty else { return offsets }
        let base = offsets[0]

        // Total fixed gap = sum of (note_offset - grace_offset) for each grace+note pair.
        let fixedTotal = graceIndices.reduce(0.0) { sum, i in
            i + 1 < offsets.count ? sum + (offsets[i + 1] - offsets[i]) : sum
        }

        let elasticNatural = naturalWidth - base - fixedTotal
        guard elasticNatural > 0 else { return offsets }
        // Compression never runs the elastic spacings past zero: the fixed parts of the
        // measure are incompressible, so there is nothing sane to do below that point.
        let elasticScale = max(0, (finalWidth - base - fixedTotal) / elasticNatural)

        var result = [Double](repeating: 0, count: offsets.count)
        var cumFixed = 0.0
        for i in 0..<offsets.count {
            if i > 0 && graceIndices.contains(i - 1) {
                // Pair-follower: preserve the fixed gap from the preceding grace event.
                let gap = offsets[i] - offsets[i - 1]
                result[i] = result[i - 1] + gap
                cumFixed += gap
            } else {
                // Elastic event: scale its position relative to the base.
                let elasticOffset = offsets[i] - base - cumFixed
                result[i] = base + cumFixed + elasticOffset * elasticScale
            }
        }
        return result
    }
}
