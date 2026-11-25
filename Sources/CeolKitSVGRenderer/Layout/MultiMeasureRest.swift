import CeolKitModel

/// How a multi-measure rest (`Zn`, n > 1; ABC v2.2 §4.5; issue #291) is spaced and drawn,
/// after abcm2ps 8.14: a thick horizontal bar on the middle line between two short vertical
/// strokes, with the number of measures centred over the staff.
///
/// The sizes are abcm2ps's, in its units, in which a staff space is 6 (`syms.c`'s `mrest`,
/// `draw.c`'s `MREST` case, `music.c`'s widths): every one is multiplied by
/// `u = staffSize / 6` before use.
///
/// `Z` and `Z1` are not multi-measure rests: abcm2ps expands them to an ordinary rest of a
/// whole measure (`mrest_expand`), and so does this renderer.  `Xn` takes the same measures
/// and draws nothing.
enum MultiMeasureRest {

    /// The length of the bar.
    static let barLength = 40.0
    /// The bar's thickness.
    static let barThickness = 5.0
    /// How far each end stroke reaches above and below the middle line: a staff space.
    static let strokeReach = 6.0
    /// The width of each end stroke.
    static let strokeWidth = 1.0
    /// The count's size: abcm2ps sets it in Times-Bold 15.
    static let fontSize = 15.0
    /// The count's baseline, above the top staff line (abcm2ps: `staff y + 28`).
    static let numberBaseline = 4.0
    /// How far the count reaches above the top staff line, for anything stacked over it
    /// (abcm2ps's `ymx = 24 + 15`).
    static let reachAbove = 15.0
    /// The room in front of the bar beyond what an ordinary note has after a bar line.
    static let leadingRoom = 4.0
    /// The room after the bar to the next symbol.
    ///
    /// abcm2ps gives a multi-measure rest 36 units either side of its centre, about what it
    /// gives a bar of four crotchets.  This renderer spaces notes far tighter than abcm2ps
    /// does at their natural width, so taking abcm2ps's room as it stands would make the
    /// rest's bar twice as wide as its neighbours: it keeps the bar's own length and the
    /// proportion instead, which is what survives justification.
    static let trailingRoom = 12.0

    /// The number of measures `rest` stands for, where it is drawn as a multi-measure rest:
    /// a visible `Z` of more than one measure.  `nil` for everything else.
    static func drawnCount(of rest: Rest) -> Int? {
        guard rest.kind == .fullMeasure, let count = rest.measureCount, count > 1 else {
            return nil
        }
        return count
    }

    /// Whether `rest` takes a multi-measure rest's room, drawn or not (`Zn` or `Xn`, n > 1).
    static func isMultiMeasure(_ rest: Rest) -> Bool {
        (rest.measureCount ?? 0) > 1
    }

    /// The column a multi-measure rest occupies, from the start of its bar to the next
    /// symbol, at `staffSize`.
    static func columnWidth(staffSize: Double) -> Double {
        (barLength + trailingRoom) * staffSize / TextStyles.nominalStaffSize
    }

    /// The SVG path of the bar and its end strokes, the bar starting at `x` and centred on
    /// `middleLineY`, as filled rectangles: no `<line>` a geometry reader could take for a
    /// staff line.
    static func path(x: Double, middleLineY y: Double, staffSize: Double) -> String {
        let fmt = SVGFormat.coordinate
        let u = staffSize / TextStyles.nominalStaffSize
        let length = barLength * u
        let half = barThickness * u / 2
        let reach = strokeReach * u
        let stroke = strokeWidth * u
        func box(_ left: Double, _ top: Double, _ width: Double, _ height: Double) -> String {
            "M\(fmt(left)) \(fmt(top))h\(fmt(width))v\(fmt(height))h\(fmt(-width))Z"
        }
        return box(x, y - half, length, 2 * half)
            + box(x - stroke / 2, y - reach, stroke, 2 * reach)
            + box(x + length - stroke / 2, y - reach, stroke, 2 * reach)
    }
}
