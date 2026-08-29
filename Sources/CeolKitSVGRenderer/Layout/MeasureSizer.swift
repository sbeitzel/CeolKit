import Foundation
import CeolKitModel

/// Pass 1: computes the natural width of a `Measure` and the x offset of each event.
///
/// Column width uses square-root proportional spacing (linear spacing is too extreme for long
/// notes) with a minimum floor so very short notes remain legible.  ``ColumnMetrics`` owns
/// those measurements, so the shared-staff merge sizes a column exactly as this does.
public struct MeasureSizer: Sendable {
    private let metrics: ColumnMetrics
    private let merger: SharedStaffMerger

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.metrics = ColumnMetrics(config: config, metadata: metadata)
        self.merger = SharedStaffMerger(metrics: metrics)
    }

    /// Sizes a single measure.
    ///
    /// - Parameters:
    ///   - measure: The measure to size.
    ///   - unitNoteLength: The voice's `L:` value (e.g. `Fraction(1, 8)` for eighth-note unit).
    ///     Used to convert `Note.duration` multipliers to an absolute quarter-note reference.
    ///   - voiceIndex: Which voice of its staff the measure belongs to.  Every event is
    ///     tagged with it, so the passes below can tell the voices of a shared staff apart
    ///     without the layout types growing a second dimension.  A staff with one voice —
    ///     which is every staff but a `( … )` group — passes `0`.
    public func size(_ measure: Measure, unitNoteLength: Fraction,
                     voiceIndex: Int = 0) -> SizedMeasure {
        // Quarter-note duration expressed in unit-note-length units.
        // e.g. unitNoteLength = 1/8 → quarterInUnits = 2.0
        let unl = Double(unitNoteLength.numerator) / Double(unitNoteLength.denominator)
        let quarterInUnits = 0.25 / unl

        var offsets: [Double] = []
        var graceEventIndices: Set<Int> = []
        var x: Double = metrics.leftMargin(for: measure)
        var i = 0

        while i < measure.events.count {
            let event = measure.events[i]

            if case .grace(let g) = event,
               i + 1 < measure.events.count,
               metrics.isSpacingEvent(measure.events[i + 1]) {
                // Grace + following note/chord/rest: treat as a combined unit so the pair
                // moves together during justification.
                let graceW = metrics.graceGroupWidth(g)
                let gap    = metrics.graceNoteGap(for: g)
                graceEventIndices.insert(offsets.count)  // record before appending
                offsets.append(x)                        // grace event
                offsets.append(x + graceW + gap)         // paired note/chord/rest
                x += graceW + gap + metrics.columnWidth(for: measure.events[i + 1],
                                                        quarterInUnits: quarterInUnits)
                i += 2
            } else {
                offsets.append(x)
                x += metrics.columnWidth(for: event, quarterInUnits: quarterInUnits)
                i += 1
            }
        }

        // Right-side padding: enough space so the thin bar of a compound closing bar
        // (final, repeat-end) clears the last note after the thick bar is anchored at
        // the measure's right edge.
        let naturalWidth = x + metrics.rightPadding(for: measure)

        return SizedMeasure(measure: measure, naturalWidth: naturalWidth, eventOffsets: offsets,
                            unitNoteLength: unitNoteLength, graceEventIndices: graceEventIndices,
                            eventVoiceIndices: Array(repeating: voiceIndex, count: offsets.count))
    }

    /// Sizes one bar of a staff several voices share (§11.1 `( … )`), merging them onto a
    /// common onset grid first.
    ///
    /// A staff whose voices all fell silent here but one is not a shared staff for this bar,
    /// and is sized as the single voice it is — which is what makes an aligner-padded voice
    /// contribute nothing at all.  See ``SharedStaffMerger``.
    public func size(sharedStaff parts: [SharedVoice]) -> SizedMeasure {
        let sounding = parts.filter { !$0.isPadding }
        if let only = sounding.count == 1 ? sounding[0] : nil {
            return size(only.measure, unitNoteLength: only.unitNoteLength,
                        voiceIndex: only.voiceIndex)
        }
        return merger.merge(parts.map {
            SharedStaffMerger.VoicePart(measure: $0.measure, unitNoteLength: $0.unitNoteLength,
                                        voiceIndex: $0.voiceIndex, isPadding: $0.isPadding)
        })
    }

    /// One voice's contribution to one bar of a shared staff.
    public struct SharedVoice: Sendable {
        public let measure: Measure
        /// The voice's own `L:`; §7.3 lets the voices of one staff differ.
        public let unitNoteLength: Fraction
        /// The voice's position within the staff, top to bottom.
        public let voiceIndex: Int
        /// `true` when ``VoiceAligner`` invented this measure to keep the staves the same
        /// length.  Padding is dropped by the merge, never spaced.
        public let isPadding: Bool

        public init(measure: Measure, unitNoteLength: Fraction, voiceIndex: Int,
                    isPadding: Bool) {
            self.measure = measure
            self.unitNoteLength = unitNoteLength
            self.voiceIndex = voiceIndex
            self.isPadding = isPadding
        }
    }
}
