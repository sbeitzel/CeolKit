/// Pass 3: distributes horizontal slack across measures so each non-last system
/// fills the full usable line width.
public struct Justifier: Sendable {

    public init() {}

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
            return justify(system, targetWidth: targetWidth, stretch: shouldStretch)
        }
    }

    // MARK: - Private

    private func justify(_ system: System, targetWidth: Double, stretch: Bool) -> JustifiedSystem {
        let naturalTotal = system.measures.reduce(0.0) { $0 + $1.naturalWidth }

        guard stretch && naturalTotal > 0 else {
            // Last system (unjustified): keep natural widths.
            let measures = system.measures.map { sized in
                JustifiedMeasure(source: sized, finalWidth: sized.naturalWidth, eventOffsets: sized.eventOffsets)
            }
            return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                                   sourceForced: system.sourceForced, clef: system.clef,
                                   keySignature: system.keySignature, meter: system.meter)
        }

        let slack = targetWidth - naturalTotal
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
        let elasticScale = (finalWidth - base - fixedTotal) / elasticNatural

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
