/// Pass 3: distributes horizontal slack across measures so each non-last system
/// fills the full usable line width.
public struct Justifier: Sendable {

    public init() {}

    /// Justifies `systems` to `usableWidth`.
    ///
    /// - Parameters:
    ///   - systems: Pass 2 output.
    ///   - usableWidth: Available horizontal space in points.
    ///   - justifyLastSystem: When `true`, the last system is also stretched to fill the line.
    public func justify(
        _ systems: [System],
        usableWidth: Double,
        justifyLastSystem: Bool
    ) -> [JustifiedSystem] {
        systems.map { system in
            let shouldStretch = !system.isLastSystem || justifyLastSystem
            return justify(system, usableWidth: usableWidth, stretch: shouldStretch)
        }
    }

    // MARK: - Private

    private func justify(_ system: System, usableWidth: Double, stretch: Bool) -> JustifiedSystem {
        let naturalTotal = system.measures.reduce(0.0) { $0 + $1.naturalWidth }

        guard stretch && naturalTotal > 0 else {
            // Last system (unjustified): keep natural widths.
            let measures = system.measures.map { sized in
                JustifiedMeasure(source: sized, finalWidth: sized.naturalWidth, eventOffsets: sized.eventOffsets)
            }
            return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                                   sourceForced: system.sourceForced, clef: system.clef,
                                   keySignature: system.keySignature)
        }

        let slack = usableWidth - naturalTotal
        let measures = system.measures.map { sized -> JustifiedMeasure in
            let share = slack * (sized.naturalWidth / naturalTotal)
            let finalWidth = sized.naturalWidth + share
            let scale = finalWidth / sized.naturalWidth
            let offsets = sized.eventOffsets.map { $0 * scale }
            return JustifiedMeasure(source: sized, finalWidth: finalWidth, eventOffsets: offsets)
        }
        return JustifiedSystem(measures: measures, isLastSystem: system.isLastSystem,
                               sourceForced: system.sourceForced, clef: system.clef,
                               keySignature: system.keySignature)
    }
}
