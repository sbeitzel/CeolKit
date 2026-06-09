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
        var bucket: [SizedMeasure] = []
        var bucketWidth: Double = 0

        for (sized, breakAfter) in measures {
            let w = sized.naturalWidth
            let headerWidth = systems.isEmpty ? firstSystemHeaderWidth : laterSystemHeaderWidth
            let availableWidth = usableWidth - headerWidth

            // Overflow: flush before adding the new measure.
            if !bucket.isEmpty && bucketWidth + w > availableWidth {
                let meterForThis: Meter? = systems.isEmpty ? meter : nil
                systems.append(System(measures: bucket, isLastSystem: false, sourceForced: false,
                                      clef: clef, keySignature: keySignature, meter: meterForThis))
                bucket = []
                bucketWidth = 0
            }

            bucket.append(sized)
            bucketWidth += w

            // Source-forced break: flush with the flag set.
            if breakAfter == .hard {
                let meterForThis: Meter? = systems.isEmpty ? meter : nil
                systems.append(System(measures: bucket, isLastSystem: false, sourceForced: true,
                                      clef: clef, keySignature: keySignature, meter: meterForThis))
                bucket = []
                bucketWidth = 0
            }
        }

        if !bucket.isEmpty {
            let meterForThis: Meter? = systems.isEmpty ? meter : nil
            systems.append(System(measures: bucket, isLastSystem: false, sourceForced: false,
                                  clef: clef, keySignature: keySignature, meter: meterForThis))
        }

        // Mark the trailing system.
        if !systems.isEmpty {
            let last = systems.removeLast()
            systems.append(System(measures: last.measures, isLastSystem: true,
                                  sourceForced: last.sourceForced, clef: clef,
                                  keySignature: keySignature, meter: last.meter))
        }

        return systems
    }
}
