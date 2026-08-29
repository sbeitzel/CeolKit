import Foundation
import CeolKitModel

/// How wide one horizontal column of music has to be, and how much room the furniture at
/// each end of a bar takes.
///
/// Split out of ``MeasureSizer`` because a shared staff (§11.1 `( … )`) needs the same
/// answers for a column that several voices contribute to, and the two must agree exactly:
/// a single-voice staff and a "shared" staff with one sounding voice have to lay out
/// identically, and they only do that if there is one implementation of the question.
///
/// Column width is square-root proportional to duration (linear spacing is far too extreme
/// for long notes) with a minimum floor so very short notes stay legible.
struct ColumnMetrics: Sendable {
    let config: SVGRenderConfig
    let metadata: BravuraMetadata
    let graceMetrics: GraceMetrics
    let accidentalMetrics: AccidentalMetrics

    init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.config = config
        self.metadata = metadata
        self.graceMetrics = GraceMetrics(config: config, metadata: metadata)
        self.accidentalMetrics = AccidentalMetrics(config: config, metadata: metadata)
    }

    // MARK: - Column width

    /// The width of the column `event` occupies.
    ///
    /// - Parameters:
    ///   - durationUnits: the duration the column is spaced *for*, in unit note lengths,
    ///     when that is not the event's own — which is the case on a shared staff, where a
    ///     column runs only as far as the next voice's onset and a note sounding across
    ///     several columns is spaced by the first of them.  `nil` (the single-voice case)
    ///     means the event's own duration.  Everything that is a property of the event
    ///     rather than of the column — accidental reservation, the dotted-note minimum —
    ///     is unaffected by it.
    func columnWidth(for event: Event, durationUnits: Double? = nil,
                     quarterInUnits: Double) -> Double {
        let s = config.staffSize
        let minCol = s * 1.2
        let base   = s * 2.0

        switch event {
        case .note(let n):
            let rawCol = base * durationFactor(durationUnits ?? rawDuration(n.duration),
                                               quarterInUnits: quarterInUnits)
            var col = max(minCol, rawCol)
            let accWidth = accidentalMetrics.reservation(for: n.displayedAccidental)
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
            return max(minCol, base * durationFactor(durationUnits ?? rawDuration(r.duration),
                                                     quarterInUnits: quarterInUnits))

        case .chord(let c):
            let col = max(minCol, base * durationFactor(durationUnits ?? rawDuration(c.duration),
                                                        quarterInUnits: quarterInUnits))
            // Chord accidentals are not yet stacked, so reserve for the widest of them.
            let accWidth = c.notes
                .map { accidentalMetrics.reservation(for: $0.displayedAccidental) }
                .max() ?? 0
            return col + accWidth

        case .tuplet(let t):
            let df = durationFactor(durationUnits ?? tupletDuration(t),
                                    quarterInUnits: quarterInUnits)
            return max(minCol, base * df)

        case .grace(let g):
            // Fallback for orphaned grace events (not immediately followed by a spacing event).
            return graceGroupWidth(g)

        case .spacer(let sp):
            guard sp.width > 0 else { return 0 }
            return s * 0.5 * Double(sp.width)

        case .directiveAnchor:
            return 0

        case .tempoChange:
            return s * 6
        }
    }

    // MARK: - Grace helpers

    /// Returns true for events that carry rhythmic duration and act as spacing anchors.
    func isSpacingEvent(_ event: Event) -> Bool {
        switch event {
        case .note, .chord, .rest: return true
        default: return false
        }
    }

    /// Width consumed by a grace group: outer padding at each edge plus one `advance`
    /// per additional notehead.  See `GraceMetrics`.
    func graceGroupWidth(_ grace: GraceGroup) -> Double {
        graceMetrics.width(grace.notes)
    }

    /// Gap between the grace group's right edge and the principal notehead.
    ///
    /// For a single grace note the 32nd-note flag extends right of the stem and overhangs the
    /// column boundary.  We measure the overhang from the bounding-box data and add a small
    /// comfortable clearance so the flag tip is visibly separated from the principal note.
    /// Multi-note groups use beams that don't overhang, so a simpler fixed gap is used there.
    func graceNoteGap(for grace: GraceGroup) -> Double {
        guard let single = grace.notes.first, grace.notes.count == 1 else {
            // Beamed group: no flag overhang; the group's own trailing pad plus a
            // notehead-quarter of clearance before the principal note.
            return noteheadWidth() * (GraceMetrics.edgePad * GraceMetrics.scale + 0.25)
        }
        // Single grace note: compute how far the flag extends past the group's right edge.
        // flagWidth (rendered) = bboxWidth × staffSize × graceScale.
        let flagW = metadata.glyphBBoxes["flag32ndUp"]
                        .map { $0.width * config.staffSize * GraceMetrics.scale }
                    ?? config.staffSize * 0.625
        let stemX        = graceMetrics.stemOffsets([single])[0]
        let flagOverhang = max(0, stemX + flagW - graceMetrics.width([single]))
        return flagOverhang + config.staffSize * 0.25
    }

    // MARK: - Bar furniture

    /// Right padding after the last event column.
    ///
    /// Compound closing bars (final, repeat-end, double) are drawn right-anchored so
    /// their trailing edge aligns with other lines' thin bar edges.  The leading bar
    /// sits to the left of that anchor — `wideSep` for the thick-barred kinds, `sep`
    /// for the thin-thin double bar — so the padding must be large enough to keep it
    /// clear of the last note.
    func rightPadding(for measure: Measure) -> Double {
        let s       = config.staffSize
        let sep     = metadata.engravingDefaults.barlineSeparation * s
        let wideSep = sep * 2.0
        switch measure.closingBar.kind {
        case .final, .repeatEnd, .repeatEndSection, .repeatBoth:
            return wideSep + s * 0.5
        case .double:
            return sep + s * 0.5
        default:
            return s * 0.5
        }
    }

    /// Left margin before the first event.
    ///
    /// For measures that begin with a start-repeat bar line the dots occupy
    /// the space immediately after the bar complex, so the first note is
    /// pushed past them before the standard one-notehead gap is added.
    /// A mid-line time-signature change adds its glyph width before the note gap.
    func leftMargin(for measure: Measure) -> Double {
        let nhw = noteheadWidth()
        let thin = metadata.engravingDefaults.thinBarlineThickness * config.staffSize
        let meterGap = measure.meter != nil ? 2.0 * thin : 0
        let timeSigW = measure.meter.map { timeSignatureWidth(for: $0, metadata: metadata, staffSize: config.staffSize) } ?? 0
        guard let opening = measure.openingBar else { return meterGap + timeSigW + nhw }
        switch opening.kind {
        case .repeatStart, .sectionRepeatStart, .repeatBoth:
            let wideSep = metadata.engravingDefaults.barlineSeparation * config.staffSize * 2.0
            // Must match `emitRepeatDots`, which places the dots by this same measurement.
            let dotSep  = metadata.engravingDefaults.repeatBarlineDotSeparation * config.staffSize
            let dotW    = metadata.glyphBBoxes["repeatDot"].map { $0.width * config.staffSize }
                          ?? config.staffSize * 0.25
            return wideSep + dotSep + dotW + meterGap + timeSigW + nhw
        default:
            return meterGap + timeSigW + nhw
        }
    }

    // MARK: - Helpers

    func noteheadWidth() -> Double {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
            ?? config.staffSize * 1.2
    }

    func augmentationDotWidth() -> Double {
        metadata.glyphBBoxes["augmentationDot"].map { $0.width * config.staffSize }
            ?? config.staffSize * 0.4
    }

    func isDottedDuration(_ dur: Fraction) -> Bool {
        let n = dur.numerator
        let d = dur.denominator
        guard n > 0, d > 0, (d & (d - 1)) == 0 else { return false }
        var m = n
        while m % 2 == 0 { m /= 2 }
        return m == 3
    }

    func durationFactor(_ durationUnits: Double, quarterInUnits: Double) -> Double {
        sqrt(max(durationUnits, 0) / quarterInUnits)
    }

    /// The written duration of a single event in unit note lengths.
    ///
    /// `0` for everything that is not a note, rest or chord — a nested tuplet included, which
    /// is why ``tupletDuration(_:)`` is only ever right about a tuplet one level deep.  That
    /// is what the sizer has always measured, and the shared-staff merge reads the same
    /// number so the two agree about where a column starts.
    func rawDuration(_ event: Event) -> Double {
        switch event {
        case .note(let n):  return rawDuration(n.duration)
        case .rest(let r):  return rawDuration(r.duration)
        case .chord(let c): return rawDuration(c.duration)
        default:            return 0
        }
    }

    /// How far an event advances the clock, in unit note lengths.
    func soundingDuration(_ event: Event) -> Double {
        if case .tuplet(let t) = event { return tupletDuration(t) }
        return rawDuration(event)
    }

    private func rawDuration(_ fraction: Fraction) -> Double {
        Double(fraction.numerator) / Double(fraction.denominator)
    }

    /// A tuplet's sounding duration in unit note lengths: the written total scaled by `q/p`.
    func tupletDuration(_ tuplet: Tuplet) -> Double {
        let written = tuplet.events.reduce(0.0) { $0 + rawDuration($1) }
        return written * Double(tuplet.q) / Double(tuplet.p)
    }
}
