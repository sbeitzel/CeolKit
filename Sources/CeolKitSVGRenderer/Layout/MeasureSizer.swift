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
    /// Opens the columns up wherever the text on the notes would otherwise collide; run on
    /// every bar either sizing path produces (issue #185).
    private let annotationSpacing: AnnotationSpacing

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.init(config: config, metadata: metadata, styles: nil)
    }

    /// - Parameter styles: how the tune's text is set (issue #186); `nil` for the defaults.
    init(config: SVGRenderConfig, metadata: BravuraMetadata, styles: TextStyles?) {
        self.metrics = ColumnMetrics(config: config, metadata: metadata, styles: styles)
        self.merger = SharedStaffMerger(metrics: metrics)
        self.annotationSpacing = AnnotationSpacing(metrics: metrics)
    }

    /// Sizes a single measure.
    ///
    /// - Parameters:
    ///   - measure: The measure to size.  Its own ``Measure/unitNoteLength`` is what converts
    ///     `Note.duration` multipliers to an absolute quarter-note reference, so a bar after a
    ///     mid-voice `L:` is sized in the unit it is actually written in (issue #122).
    ///   - voiceIndex: Which voice of its staff the measure belongs to.  Every event is
    ///     tagged with it, so the passes below can tell the voices of a shared staff apart
    ///     without the layout types growing a second dimension.  A staff with one voice —
    ///     which is every staff but a `( … )` group — passes `0`.
    ///   - keyChange: The key change engraved before this measure's first note, where
    ///     ``Measure/key`` says the key moved here (issue #129).  Resolved by the caller,
    ///     which is the only place that knows the key the staff was in and the clef it
    ///     carries; the signature's glyphs are reserved for at the head of the bar.
    ///   - ownsOpeningBar: Whether the measure's opening bar was written in its own right —
    ///     after a bar of its own, or at the head of the tune — rather than being the previous
    ///     measure's closing bar.  Only the caller, which walks the voice in order, can say.
    ///     See ``SizedMeasure/openingBarLead``.
    ///   - atSystemStart: Whether the measure is being sized to open a system, where an
    ///     opening bar it owns stands at the head of the staff rather than after another bar.
    public func size(_ measure: Measure, voiceIndex: Int = 0,
                     keyChange: KeyChange? = nil,
                     ownsOpeningBar: Bool = false,
                     atSystemStart: Bool = false) -> SizedMeasure {
        let unitNoteLength = measure.unitNoteLength
        // Quarter-note duration expressed in unit-note-length units.
        // e.g. unitNoteLength = 1/8 → quarterInUnits = 2.0
        let unl = Double(unitNoteLength.numerator) / Double(unitNoteLength.denominator)
        let quarterInUnits = 0.25 / unl

        var offsets: [Double] = []
        var graceEventIndices: Set<Int> = []
        var x: Double = metrics.leftMargin(for: measure, keyChange: keyChange,
                                           ownsOpeningBar: ownsOpeningBar,
                                           atSystemStart: atSystemStart)
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
                x += graceW + gap + metrics.columnWidth(
                    for: measure.events[i + 1], quarterInUnits: quarterInUnits,
                    followedBy: nextSpacingEvent(after: i + 1, in: measure.events))
                i += 2
            } else {
                offsets.append(x)
                x += metrics.columnWidth(
                    for: event, quarterInUnits: quarterInUnits,
                    followedBy: nextSpacingEvent(after: i, in: measure.events))
                i += 1
            }
        }

        // Right-side padding: enough space so the thin bar of a compound closing bar
        // (final, repeat-end) clears the last note after the thick bar is anchored at
        // the measure's right edge.
        let naturalWidth = x + metrics.rightPadding(for: measure)

        return annotationSpacing.widen(SizedMeasure(
            measure: measure, naturalWidth: naturalWidth, eventOffsets: offsets,
            unitNoteLength: unitNoteLength, graceEventIndices: graceEventIndices,
            eventVoiceIndices: Array(repeating: voiceIndex, count: offsets.count),
            keyChange: keyChange,
            ownsOpeningBar: ownsOpeningBar,
            openingBarLead: metrics.openingBarLead(for: measure, ownsOpeningBar: ownsOpeningBar,
                                                   atSystemStart: atSystemStart)))
    }

    /// The next event of the bar that a column runs to.  A column is spaced for the syllable
    /// at each of its ends (§4.18), and this is the far one.
    private func nextSpacingEvent(after index: Int, in events: [Event]) -> Event? {
        events[(index + 1)...].first { metrics.isSpacingEvent($0) }
    }

    /// Sizes one bar of a staff several voices share (§11.1 `( … )`), merging them onto a
    /// common onset grid first.
    ///
    /// A staff whose voices all fell silent here but one is not a shared staff for this bar,
    /// and is sized as the single voice it is — which is what makes an aligner-padded voice
    /// contribute nothing at all.  See ``SharedStaffMerger``.
    ///
    /// `keyChange` is the staff's, not a voice's: §7.3 makes a `K:` belong to the voice that
    /// wrote it, but one staff carries one signature, and the lead voice is the one whose
    /// clef and key the staff head already draws.  So is `ownsOpeningBar`, for the same
    /// reason: the staff draws its first sounding voice's bar lines.
    public func size(sharedStaff parts: [SharedVoice], keyChange: KeyChange? = nil,
                     ownsOpeningBar: Bool = false,
                     atSystemStart: Bool = false) -> SizedMeasure {
        let sounding = parts.filter { !$0.isPadding }
        if let only = sounding.count == 1 ? sounding[0] : nil {
            return size(only.measure, voiceIndex: only.voiceIndex, keyChange: keyChange,
                        ownsOpeningBar: ownsOpeningBar, atSystemStart: atSystemStart)
        }
        return annotationSpacing.widen(merger.merge(parts.map {
            SharedStaffMerger.VoicePart(measure: $0.measure, voiceIndex: $0.voiceIndex,
                                        isPadding: $0.isPadding)
        }, keyChange: keyChange, ownsOpeningBar: ownsOpeningBar,
           atSystemStart: atSystemStart))
    }

    /// One voice's contribution to one bar of a shared staff.
    public struct SharedVoice: Sendable {
        /// The bar to size.  It carries the unit note length its own durations are counted
        /// in, which §7.3 lets the voices of one staff differ over.
        public let measure: Measure
        /// The voice's position within the staff, top to bottom.
        public let voiceIndex: Int
        /// `true` when ``VoiceAligner`` invented this measure to keep the staves the same
        /// length.  Padding is dropped by the merge, never spaced.
        public let isPadding: Bool

        public init(measure: Measure, voiceIndex: Int, isPadding: Bool) {
            self.measure = measure
            self.voiceIndex = voiceIndex
            self.isPadding = isPadding
        }
    }
}
