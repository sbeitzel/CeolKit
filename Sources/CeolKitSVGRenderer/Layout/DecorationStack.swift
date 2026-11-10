import CeolKitModel

/// Where the marks written on a note go (issue #264): which side of the note, how near,
/// and in what order — abcm2ps's placement, worked out once for the emitter that draws
/// them and for ``VerticalLayoutEngine``, which reserves room for them, so the two agree.
///
/// abcm2ps sets a note's marks in two passes.  Its `d_near` marks — staccato and tenuto —
/// go first, against the notehead on the side away from the stem, centred in the next
/// space out from it.  Its `d_upstaff` marks go after, outside the staff: `y_get` finds
/// how far the note's column already reaches — heads, stem or beam, a grace group, the
/// near marks — never nearer the staff than just outside it, and the mark is set there
/// and the column extended by its height for the next.  `THe` therefore draws the trill
/// nearest the note and the fermata beyond it, as written.
///
/// Everything here is in staff spaces, y increasing downward from the top staff line, so
/// the bottom line is at 4 and a head at staff position `p` (0 the bottom line, 8 the top)
/// is centred at `(8 - p) / 2`.
enum DecorationStack {

    /// One mark.
    enum Mark: Equatable {
        /// A SMuFL glyph, drawn centred on the note.
        case glyph(SMuFLGlyph)
        /// An Irish roll: the small arc abcm2ps draws for `~` (its `cpu`), opening toward
        /// the note.  SMuFL has no glyph for it, so it is drawn as a path.
        case roll
    }

    /// How a decoration is placed.
    enum Placement {
        /// Against the notehead, in the next space out, nearest of all: `d_near`.  On the
        /// side away from the stem, or on a shared staff the part's own side.
        case near
        /// Outside the staff on the side away from the stem, or on a shared staff the
        /// part's own side: the accent, which abcm2ps turns under a stem-up note.
        case opposite
        /// Outside the staff over the note, or under it for the part stemmed down on a
        /// shared staff: the ornaments, the fermata, marcato and wedge.
        case outside
        /// Outside the staff under the note, whichever part: the inverted fermata.
        case below
    }

    /// How `decoration` is placed, or `nil` for one drawn some other way (or, as yet, not
    /// at all).
    static func placement(of decoration: Decoration) -> Placement? {
        switch decoration {
        case .staccato, .tenuto:
            return .near
        case .accent:
            return .opposite
        case .trill, .mordent, .pralltriller, .turn, .invertedTurn, .roll, .fermata,
             .strongAccent, .staccatissimo:
            return .outside
        case .invertedFermata:
            return .below
        default:
            return nil
        }
    }

    /// The mark `decoration` draws on the given side of the note.
    static func mark(for decoration: Decoration, above: Bool) -> Mark? {
        switch decoration {
        case .staccato:        return .glyph(above ? .articStaccatoAbove : .articStaccatoBelow)
        case .tenuto:          return .glyph(above ? .articTenutoAbove : .articTenutoBelow)
        case .accent:          return .glyph(above ? .articAccentAbove : .articAccentBelow)
        case .strongAccent:    return .glyph(above ? .articMarcatoAbove : .articMarcatoBelow)
        case .staccatissimo:
            return .glyph(above ? .articStaccatissimoWedgeAbove : .articStaccatissimoWedgeBelow)
        case .trill:           return .glyph(.ornamentTrill)
        case .mordent:         return .glyph(.ornamentMordent)
        case .pralltriller:    return .glyph(.ornamentShortTrill)
        case .turn:            return .glyph(.ornamentTurn)
        case .invertedTurn:    return .glyph(.ornamentTurnInverted)
        case .roll:            return .roll
        case .fermata:         return .glyph(above ? .fermataAbove : .fermataBelow)
        case .invertedFermata: return .glyph(.fermataBelow)
        default:               return nil
        }
    }

    // MARK: - Planning

    /// What a note reaches, as far as its marks are concerned.
    struct Column {
        /// The centre of each of its heads.
        var headYs: [Double]
        /// Which way its stem goes — whether or not one is drawn, as a whole note's is not.
        var stemUp: Bool
        /// The end of its stem or beam, where one is drawn.
        var stemTipY: Double?
        /// The top of a grace group written in front of it.
        var graceTopY: Double?
        /// It is on a staff more than one part shares.
        var shared: Bool = false
        /// Its part sets its marks under the staff: the one stemmed down on a shared staff.
        var flipped: Bool = false
    }

    /// One mark as placed.
    struct Placed: Equatable {
        let mark: Mark
        let above: Bool
        /// Where the glyph's baseline goes — for a roll, the line its ends stand on.
        let baselineY: Double
        /// It is set over the stem tip, not the notehead: a near mark on the stem's side.
        let atStem: Bool
    }

    struct Plan {
        var marks: [Placed] = []
        /// Where a further mark outside the staff would start, over it and under it.
        var nextAbove: Double
        var nextBelow: Double
        /// The outer edge of the outermost mark each side, where there is one.
        var outerAbove: Double?
        var outerBelow: Double?
    }

    /// Places the marks of `decorations` on the note `column` describes.
    static func plan(_ decorations: [Decoration], column: Column,
                     metadata: BravuraMetadata) -> Plan {
        // Which side each decoration goes on, in the order written.
        var near: [Bool: [Decoration]] = [:]
        var outer: [Bool: [Decoration]] = [:]
        let awayFromStem = column.shared ? !column.flipped : !column.stemUp
        for decoration in decorations {
            switch placement(of: decoration) {
            case .near:     near[awayFromStem, default: []].append(decoration)
            case .opposite: outer[awayFromStem, default: []].append(decoration)
            case .outside:  outer[!column.flipped, default: []].append(decoration)
            case .below:    outer[false, default: []].append(decoration)
            case nil:       break
            }
        }

        var plan = Plan(nextAbove: 0, nextBelow: 0)
        for above in [true, false] {
            let out = above ? -1.0 : 1.0
            // The outermost of `a` and `b`, going outward on this side.
            func outermost(_ a: Double, _ b: Double) -> Double { above ? min(a, b) : max(a, b) }

            let outerHeadY = above ? (column.headYs.min() ?? 2) : (column.headYs.max() ?? 2)
            var reach = outerHeadY + out * 0.5
            let tip = column.stemUp == above ? column.stemTipY : nil
            if let tip { reach = outermost(reach, tip) }
            if above, let grace = column.graceTopY { reach = outermost(reach, grace) }

            // The near marks: in the spaces beyond the head, or beyond a stem on this side.
            var nearEdge: Double?
            let outerHeadPos = Int((8 - 2 * outerHeadY).rounded())
            var space = outerHeadPos + (above ? 1 : -1) * (outerHeadPos.isMultiple(of: 2) ? 3 : 2)
            for decoration in near[above] ?? [] {
                guard let mark = mark(for: decoration, above: above) else { continue }
                let (ascent, descent) = extent(of: mark, above: above, metadata: metadata)
                let baseline: Double
                if let tip {
                    let inner = (nearEdge.map { $0 + out * markGap } ?? tip + out * noteGap)
                    baseline = above ? inner - descent : inner + ascent
                } else {
                    let centre = Double(8 - space) / 2
                    baseline = centre + (ascent - descent) / 2
                    space += above ? 2 : -2
                }
                plan.marks.append(Placed(mark: mark, above: above, baselineY: baseline,
                                         atStem: tip != nil))
                nearEdge = above ? baseline - ascent : baseline + descent
            }

            // The marks outside the staff, beyond everything the note and its near marks
            // reach.
            let staffEdge = above ? -staffGap : 4 + staffGap
            var base = outermost(staffEdge, reach + out * noteGap)
            if let nearEdge { base = outermost(base, nearEdge + out * markGap) }
            var outerEdge = nearEdge
            for decoration in outer[above] ?? [] {
                guard let mark = mark(for: decoration, above: above) else { continue }
                let (ascent, descent) = extent(of: mark, above: above, metadata: metadata)
                let baseline = above ? base - descent : base + ascent
                plan.marks.append(Placed(mark: mark, above: above, baselineY: baseline, atStem: false))
                let edge = above ? baseline - ascent : baseline + descent
                outerEdge = edge
                base = edge + out * markGap
            }
            if above {
                plan.nextAbove = base
                plan.outerAbove = outerEdge
            } else {
                plan.nextBelow = base
                plan.outerBelow = outerEdge
            }
        }
        return plan
    }

    // MARK: - Metrics (staff spaces)

    /// Space between the note's own reach and the first mark outside it.
    static let noteGap = 0.5
    /// The least distance from the outer staff line to a mark outside the staff.
    static let staffGap = 1.0
    /// Space between one mark and the next.
    static let markGap = 0.25

    /// The roll's arc, in staff spaces from its centre on the baseline: abcm2ps's `cpu`
    /// (11.7 × 7.3 control points at 6 points a space), whose outer curve peaks at ¾ of its
    /// control height and inner curve leaves it about a sixth of a space thick.
    static let rollHalfWidth = 0.975
    static let rollOuterControl = 1.22
    static let rollInnerControl = 1.0
    static var rollHeight: Double { 0.75 * rollOuterControl }

    /// How far `mark` extends above its baseline and below it.  A glyph's box comes from
    /// its metadata; a roll arches away from the note.
    static func extent(of mark: Mark, above: Bool,
                       metadata: BravuraMetadata) -> (ascent: Double, descent: Double) {
        switch mark {
        case .glyph(let glyph):
            guard let box = metadata.glyphBBoxes[glyph.rawValue] else { return (1.0, 0) }
            return (box.neY, -box.swY)
        case .roll:
            return above ? (rollHeight, 0) : (0, rollHeight)
        }
    }

    // MARK: - Arpeggio

    /// `!arpeggio!`: a wavy line up the left of the chord, as abcm2ps's `d_arp` draws it,
    /// from half a space under the lowest head to two thirds of one over the highest, never
    /// shorter than two spaces.  Its periods are Bravura's `wiggleArpeggiatoUp`, turned to
    /// run upward, so the glyph's height is the line's width.
    static let arpeggioAdvance = 1.02
    static let arpeggioWidth = 0.476
    /// From the line to the notehead, or to the accidental where there is one.
    static let arpeggioHeadGap = 0.4
    static let arpeggioAccidentalGap = 0.35
    /// Kept clear in front of the line: with the gap and the line, abcm2ps's 14 points.
    static let arpeggioClearance = 0.85

    /// How far left of the notehead's left edge the line's right edge stands, in points,
    /// given how much room the chord's accidentals take there.
    static func arpeggioInset(accidentalReservation: Double, staffSize s: Double) -> Double {
        accidentalReservation > 0
            ? accidentalReservation + arpeggioAccidentalGap * s
            : arpeggioHeadGap * s
    }

    /// The room an arpeggio needs in front of its chord's noteheads, in points.
    static func arpeggioLead(accidentalReservation: Double, staffSize s: Double) -> Double {
        arpeggioInset(accidentalReservation: accidentalReservation, staffSize: s)
            + (arpeggioWidth + arpeggioClearance) * s
    }

    /// How one period of `wiggleTrill` advances, in staff spaces: Bravura's advance
    /// width, which its metadata does not carry.  Periods set this far apart join up.
    static let wiggleAdvance = 0.948
}
