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
            let scale = finalWidth / sized.naturalWidth
            // Scale event positions relative to the first event so the leading margin
            // (bar line / repeat dots → first note) stays fixed at its natural size.
            let base = sized.eventOffsets.first ?? 0
            let offsets = sized.eventOffsets.map { base + ($0 - base) * scale }
            return JustifiedMeasure(source: sized, finalWidth: finalWidth, eventOffsets: offsets)
        }
        return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                               sourceForced: system.sourceForced, clef: system.clef,
                               keySignature: system.keySignature, meter: system.meter)
    }
}
