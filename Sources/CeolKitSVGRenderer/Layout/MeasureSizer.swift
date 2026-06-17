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
        var x: Double = leftMargin(for: measure)
        var i = 0

        while i < measure.events.count {
            let event = measure.events[i]

            if case .grace(let g) = event,
               i + 1 < measure.events.count,
               isSpacingEvent(measure.events[i + 1]) {
                // Grace + following note/chord/rest: treat as a combined unit so the pair
                // moves together during justification.
                let graceW = graceGroupWidth(g)
                let gap    = graceNoteGap(for: g)
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

        // Right-side padding: enough space so the thin bar of a compound closing bar
        // (final, repeat-end) clears the last note after the thick bar is anchored at
        // the measure's right edge.
        let naturalWidth = x + rightPadding(for: measure)

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
            let rawCol = base * durationFactor(n.duration, quarterInUnits: quarterInUnits)
            var col = max(minCol, rawCol)
            let accWidth = n.displayedAccidental != nil ? s * 0.75 : 0
            // Very short notes (at the minimum floor) get a dot-gap equivalent of extra space
            // so consecutive beamed notes aren't visually pressed against each other.
            let breathingRoom = rawCol < minCol ? noteheadWidth() * 0.2 : 0
            // Dotted notes need enough column to clear the augmentation dot before the next note.
            // Minimum = notehead + dotGap + dotWidth + clearance = noteheadWidth × 1.4 + dotWidth.
            if isDottedDuration(n.duration) {
                col = max(col, noteheadWidth() * 1.4 + augmentationDotWidth())
            }
            return col + accWidth + breathingRoom

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
            guard sp.width > 0 else { return 0 }
            return s * 0.5 * Double(sp.width)

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

    /// Gap between the grace group's last column boundary and the principal notehead.
    ///
    /// For a single grace note the 32nd-note flag extends right of the stem and overhangs the
    /// column boundary.  We measure the overhang from the bounding-box data and add a small
    /// comfortable clearance so the flag tip is visibly separated from the principal note.
    /// Multi-note groups use beams that don't overhang, so a simpler fixed gap is used there.
    private func graceNoteGap(for grace: GraceGroup) -> Double {
        let graceNHW = noteheadWidth() * 0.6   // grace notehead width (graceScale = 0.6)
        guard grace.notes.count == 1 else {
            // Beamed group: no flag overhang; keep original gap.
            return noteheadWidth() * (0.25 * 0.6 + 0.25)
        }
        // Single grace note: compute how far the flag extends past the column boundary.
        // stemX within the column = 1.25 × graceNHW; columnWidth = 1.5 × graceNHW.
        // flagWidth (rendered) = bboxWidth × staffSize × 0.6.
        let flagW = metadata.glyphBBoxes["flag32ndUp"].map { $0.width * config.staffSize * 0.6 }
                    ?? config.staffSize * 0.625
        let flagOverhang = max(0, 1.25 * graceNHW + flagW - 1.5 * graceNHW)
        return flagOverhang + config.staffSize * 0.25
    }

    // MARK: - Helpers

    private func noteheadWidth() -> Double {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
            ?? config.staffSize * 1.2
    }

    /// Right padding after the last event column.
    ///
    /// Compound closing bars (final, repeat-end) are drawn right-anchored so their
    /// thick bar's trailing edge aligns with other lines' thin bar edges.  The thin
    /// bar sits `wideSep` to the left of that anchor, so the padding must be large
    /// enough to keep the thin bar clear of the last note.
    private func rightPadding(for measure: Measure) -> Double {
        let s       = config.staffSize
        let sep     = metadata.engravingDefaults.barlineSeparation * s
        let wideSep = sep * 2.0
        switch measure.closingBar.kind {
        case .final, .repeatEnd, .repeatEndSection, .repeatBoth:
            return wideSep + s * 0.5
        default:
            return s * 0.5
        }
    }

    /// Left margin before the first event.
    ///
    /// For measures that begin with a start-repeat bar line the dots occupy
    /// the space immediately after the bar complex, so the first note is
    /// pushed past them before the standard one-notehead gap is added.
    private func leftMargin(for measure: Measure) -> Double {
        let nhw = noteheadWidth()
        guard let opening = measure.openingBar else { return nhw }
        switch opening.kind {
        case .repeatStart, .sectionRepeatStart, .repeatBoth:
            let sep     = metadata.engravingDefaults.barlineSeparation * config.staffSize
            let wideSep = sep * 2.0
            let dotW    = metadata.glyphBBoxes["repeatDot"].map { $0.width * config.staffSize }
                          ?? config.staffSize * 0.25
            return wideSep + sep + dotW + nhw
        default:
            return nhw
        }
    }

    private func augmentationDotWidth() -> Double {
        metadata.glyphBBoxes["augmentationDot"].map { $0.width * config.staffSize }
            ?? config.staffSize * 0.4
    }

    private func isDottedDuration(_ dur: Fraction) -> Bool {
        let n = dur.numerator
        let d = dur.denominator
        guard n > 0, d > 0, (d & (d - 1)) == 0 else { return false }
        var m = n
        while m % 2 == 0 { m /= 2 }
        return m == 3
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
