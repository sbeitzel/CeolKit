import CeolKitModel

/// Pass 2: groups `SizedMeasure` values into `System` rows using greedy first-fit.
///
/// Source-forced breaks (`.hard` `ScoreLineBreak`) close the current system immediately,
/// regardless of accumulated width.
public struct LineBreaker: Sendable {

    public init() {}

    /// Breaks `measures` into systems.
    ///
    /// - Parameters:
    ///   - measures: Pass 1 output paired with an optional source line-break hint that follows
    ///     each measure. `nil` or `.soft`/`.suppressed` leaves the greedy algorithm in charge;
    ///     `.hard` forces a system break after that measure.
    ///   - usableWidth: Available horizontal space in points (page width minus left/right margins).
    public func breakIntoSystems(
        _ measures: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)],
        usableWidth: Double
    ) -> [System] {
        var systems: [System] = []
        var bucket: [SizedMeasure] = []
        var bucketWidth: Double = 0

        for (sized, breakAfter) in measures {
            let w = sized.naturalWidth

            // Overflow: flush before adding the new measure.
            if !bucket.isEmpty && bucketWidth + w > usableWidth {
                systems.append(System(measures: bucket, isLastSystem: false, sourceForced: false))
                bucket = []
                bucketWidth = 0
            }

            bucket.append(sized)
            bucketWidth += w

            // Source-forced break: flush with the flag set.
            if breakAfter == .hard {
                systems.append(System(measures: bucket, isLastSystem: false, sourceForced: true))
                bucket = []
                bucketWidth = 0
            }
        }

        if !bucket.isEmpty {
            systems.append(System(measures: bucket, isLastSystem: false, sourceForced: false))
        }

        // Mark the trailing system.
        if !systems.isEmpty {
            let last = systems.removeLast()
            systems.append(System(measures: last.measures, isLastSystem: true, sourceForced: last.sourceForced))
        }

        return systems
    }
}
