import Foundation
import CeolKitModel

/// Pass 1: computes the natural width of a `Measure` and the x offset of each event.
///
/// Column width uses square-root proportional spacing (linear spacing is too extreme for long
/// notes) with a minimum floor so very short notes remain legible.
public struct MeasureSizer: Sendable {
    private let config: SVGRenderConfig
    private let metadata: BravuraMetadata

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.config = config
        self.metadata = metadata
    }

    /// Sizes a single measure.
    ///
    /// - Parameters:
    ///   - measure: The measure to size.
    ///   - unitNoteLength: The voice's `L:` value (e.g. `Fraction(1, 8)` for eighth-note unit).
    ///     Used to convert `Note.duration` multipliers to an absolute quarter-note reference.
    public func size(_ measure: Measure, unitNoteLength: Fraction) -> SizedMeasure {
        // Quarter-note duration expressed in unit-note-length units.
        // e.g. unitNoteLength = 1/8 → quarterInUnits = 2.0
        let unl = Double(unitNoteLength.numerator) / Double(unitNoteLength.denominator)
        let quarterInUnits = 0.25 / unl

        var offsets: [Double] = []
        var x: Double = 0
        var i = 0

        while i < measure.events.count {
            let event = measure.events[i]

            if case .grace(let g) = event,
               i + 1 < measure.events.count,
               isSpacingEvent(measure.events[i + 1]) {
                // Grace + following note/chord/rest: treat as a combined unit so the pair
                // moves together during justification. The gap between the grace group's
                // last notehead and the principal note is fixed at
                // 0.25 × grace notehead width + 0.25 × normal notehead width.
                let graceW = graceGroupWidth(g)
                let gap    = graceNoteGap()
                offsets.append(x)                    // grace event
                offsets.append(x + graceW + gap)     // paired note/chord/rest
                x += graceW + gap + columnWidth(for: measure.events[i + 1], quarterInUnits: quarterInUnits)
                i += 2
            } else {
                offsets.append(x)
                x += columnWidth(for: event, quarterInUnits: quarterInUnits)
                i += 1
            }
        }

        // Right-side padding for the closing bar line.
        let naturalWidth = x + config.staffSize * 0.5

        return SizedMeasure(measure: measure, naturalWidth: naturalWidth, eventOffsets: offsets,
                            unitNoteLength: unitNoteLength)
    }

    // MARK: - Column width

    private func columnWidth(for event: Event, quarterInUnits: Double) -> Double {
        let s = config.staffSize
        let minCol = s * 1.2
        let base   = s * 2.0

        switch event {
        case .note(let n):
            let col = max(minCol, base * durationFactor(n.duration, quarterInUnits: quarterInUnits))
            let accWidth = n.displayedAccidental != nil ? s * 0.75 : 0
            return col + accWidth

        case .rest(let r):
            return max(minCol, base * durationFactor(r.duration, quarterInUnits: quarterInUnits))

        case .chord(let c):
            let col = max(minCol, base * durationFactor(c.duration, quarterInUnits: quarterInUnits))
            let hasAcc = c.notes.contains { $0.displayedAccidental != nil }
            return col + (hasAcc ? s * 0.75 : 0)

        case .tuplet(let t):
            var totalUnits = 0.0
            for e in t.events { totalUnits += rawDuration(e) }
            let adjustedUnits = totalUnits * Double(t.q) / Double(t.p)
            let df = sqrt(max(adjustedUnits, 0) / quarterInUnits)
            return max(minCol, base * df)

        case .grace(let g):
            // Fallback for orphaned grace events (not immediately followed by a spacing event).
            return graceGroupWidth(g)

        case .spacer(let sp):
            return s * 0.5 * Double(max(sp.width, 1))

        case .directiveAnchor:
            return 0
        }
    }

    // MARK: - Grace helpers

    /// Returns true for events that carry rhythmic duration and act as spacing anchors.
    private func isSpacingEvent(_ event: Event) -> Bool {
        switch event {
        case .note, .chord, .rest: return true
        default: return false
        }
    }

    /// Width consumed by a grace group: 1.5 × grace notehead width per note,
    /// giving 0.25× leading and 0.25× trailing padding (0.5× between adjacent noteheads).
    private func graceGroupWidth(_ grace: GraceGroup) -> Double {
        noteheadWidth() * 0.6 * 1.5 * Double(max(grace.notes.count, 1))
    }

    /// Fixed gap between the last grace notehead's right edge and the principal notehead:
    /// 0.25 × grace notehead width + 0.25 × normal notehead width.
    private func graceNoteGap() -> Double {
        noteheadWidth() * (0.25 * 0.6 + 0.25)
    }

    // MARK: - Helpers

    private func noteheadWidth() -> Double {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
            ?? config.staffSize * 1.2
    }

    private func durationFactor(_ duration: Fraction, quarterInUnits: Double) -> Double {
        let d = Double(duration.numerator) / Double(duration.denominator)
        return sqrt(max(d, 0) / quarterInUnits)
    }

    private func rawDuration(_ event: Event) -> Double {
        switch event {
        case .note(let n):  return Double(n.duration.numerator) / Double(n.duration.denominator)
        case .rest(let r):  return Double(r.duration.numerator) / Double(r.duration.denominator)
        case .chord(let c): return Double(c.duration.numerator) / Double(c.duration.denominator)
        default:            return 0
        }
    }
}
