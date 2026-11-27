import CeolKitModel

/// Where a rest that fills its whole measure stands (issue #300): centred in the measure,
/// as abcm2ps 8.14 draws it, rather than at the left where a first note would stand.
///
/// abcm2ps's `draw_rest` (`draw.c`) centres a rest whose length is a whole measure halfway
/// between the symbol before it and the next one, and moves its decorations with it.  Here
/// that is:
///
/// - `Z`/`Z1` and `X`/`X1`, and any `z`/`x` lasting exactly one measure of the meter in
///   force (`z4` in `M:4/4 L:1/4`);
/// - a multi-measure rest, `Zn`/`Xn` with n > 1 (#291), whose bar would otherwise start
///   at the first note's place and drift left of centre once the line is justified;
/// - only where the rest is the only thing in its measure.  On a shared staff a rest
///   beside another voice's notes keeps its column.
///
/// The rest is centred between the end of whatever opens the measure — its bar line, the
/// dots of a start-repeat, a signature drawn at the head of the bar, or the clef and key
/// at the start of a system — and its closing bar line.
enum CentredRest {

    /// `jm`'s event offsets, with the rest that fills the measure moved to its centre.
    /// The offsets are returned as they were where nothing is centred.
    ///
    /// - Parameters:
    ///   - measureLength: the length of one measure of the meter in force, in whole notes,
    ///     or `nil` where it is not known or there is none (`M:none`).  Without it only a
    ///     full-measure rest (`Z`, `X`) is centred.
    ///   - metadata: what the rest's glyph is measured in.  `nil` measures with the
    ///     notehead's nominal width, which is close enough for a multi-measure rest, whose
    ///     bar is not a glyph.
    static func offsets(of jm: JustifiedMeasure, measureLength: Fraction?,
                        metadata: BravuraMetadata?, staffSize s: Double) -> [Double] {
        var offsets = jm.eventOffsets
        let events = jm.source.measure.events
        guard let index = loneRestIndex(in: events), index < offsets.count,
              case .rest(let rest) = events[index],
              fillsMeasure(rest, unitNoteLength: jm.source.measure.unitNoteLength,
                           measureLength: measureLength)
        else { return offsets }

        let u = s / TextStyles.nominalStaffSize
        let noteheadWidth = metadata?.glyphBBoxes["noteheadBlack"].map { $0.width * s } ?? s * 1.2
        // The bar's first event — whitespace before the rest, often — stands at the bar's
        // left margin, which justification never moves: a notehead's width after whatever
        // opens the bar (``ColumnMetrics/leftMargin(for:keyChange:ownsOpeningBar:atSystemStart:)``).
        // A multi-measure rest is given room beyond that, but only in its own offset.
        let lead = noteheadWidth
            + (index == 0 && MultiMeasureRest.isMultiMeasure(rest)
               ? MultiMeasureRest.leadingRoom * u : 0)
        let left = offsets[0] - lead
        let width = drawnWidth(of: rest, unitNoteLength: jm.source.measure.unitNoteLength,
                               metadata: metadata, staffSize: s)
        let centred = (left + jm.finalWidth) / 2 - width / 2
        // Never further left than the sizer put it: in a bar too narrow to centre in, the
        // rest keeps clear of what opens the bar.
        offsets[index] = max(offsets[index], centred)
        return offsets
    }

    /// The width a rest is drawn at, from its left edge: a multi-measure rest's bar, or the
    /// glyph it is drawn with.  An invisible rest is measured as a visible one would be.
    static func drawnWidth(of rest: Rest, unitNoteLength: Fraction,
                           metadata: BravuraMetadata?, staffSize s: Double) -> Double {
        if MultiMeasureRest.isMultiMeasure(rest) {
            return MultiMeasureRest.barLength * s / TextStyles.nominalStaffSize
        }
        let glyph = glyph(for: rest, unitNoteLength: unitNoteLength)
        return (metadata?.glyphBBoxes[glyph.rawValue]?.width ?? 1) * s
    }

    /// The glyph a rest that is not a multi-measure rest is drawn with: a full-measure rest
    /// (`Z`) as a whole rest, anything else by its written length.
    static func glyph(for rest: Rest, unitNoteLength: Fraction) -> SMuFLGlyph {
        if rest.measureCount != nil { return .restWhole }
        let d = rest.duration.denominator == 0 || unitNoteLength.denominator == 0 ? 0
            : Double(rest.duration.numerator) / Double(rest.duration.denominator)
              * Double(unitNoteLength.numerator) / Double(unitNoteLength.denominator)
        switch d {
        case 1...:      return .restWhole
        case 0.5...:    return .restHalf
        case 0.25...:   return .restQuarter
        case 0.125...:  return .rest8th
        case 0.0625...: return .rest16th
        case 0.03125...: return .rest32nd
        default:        return .rest64th
        }
    }

    /// The length of one measure of `meter` in whole notes, or `nil` for `M:none` and a
    /// meter that cannot have one.
    static func measureLength(_ meter: Meter) -> Fraction? {
        switch meter {
        case .fraction(let num, let den):
            return den > 0 ? Fraction(numerator: num, denominator: den) : nil
        case .commonTime, .cutTime:
            return Fraction(numerator: 1, denominator: 1)
        case .complex(let parts, let den):
            return den > 0 ? Fraction(numerator: parts.reduce(0, +), denominator: den) : nil
        case .free:
            return nil
        }
    }

    // MARK: - Private

    /// The index of the measure's one rest, where it is the only thing in the measure that
    /// takes a place on the staff.  Directives, tempo changes and a clef change before the
    /// music (which is drawn at the end of the bar before) do not count.
    private static func loneRestIndex(in events: [Event]) -> Int? {
        var found: Int?
        var seenMusic = false
        for (i, event) in events.enumerated() {
            switch event {
            case .directiveAnchor, .tempoChange:
                continue
            case .spacer(let spacer) where spacer.width == 0:
                // Whitespace, which only breaks beams; a `y` takes room and does count.
                continue
            case .clefChange where !seenMusic:
                continue
            case .rest:
                guard found == nil, !seenMusic else { return nil }
                found = i
                seenMusic = true
            default:
                return nil
            }
        }
        return found
    }

    /// Whether `rest` lasts exactly one measure, or is a full-measure rest of any count.
    private static func fillsMeasure(_ rest: Rest, unitNoteLength unl: Fraction,
                                     measureLength: Fraction?) -> Bool {
        if rest.measureCount != nil { return true }
        guard let m = measureLength, m.numerator > 0, m.denominator > 0,
              rest.duration.denominator != 0, unl.denominator != 0 else { return false }
        // duration × unit = measure, cross-multiplied so it stays exact.
        let lhs = rest.duration.numerator.multipliedReportingOverflow(by: unl.numerator)
        let rhs = rest.duration.denominator.multipliedReportingOverflow(by: unl.denominator)
        guard !lhs.overflow, !rhs.overflow else { return false }
        let a = lhs.partialValue.multipliedReportingOverflow(by: m.denominator)
        let b = rhs.partialValue.multipliedReportingOverflow(by: m.numerator)
        guard !a.overflow, !b.overflow else { return false }
        return a.partialValue == b.partialValue && a.partialValue != 0
    }
}
