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
        /// A repeat instruction in words — "D.C. al Fine", "Fine" — set in italic, as Gould
        /// sets them (*Behind Bars*, p. 240).
        case words(String)
        /// `!dacoda!`: "Da" and a coda sign after it.
        case daCoda
    }

    /// How a mark stands against the x it is given.
    enum Anchor: Equatable {
        /// Centred on it: a mark on a note, or the segno and coda over a bar line.
        case centre
        /// Ending at it: words on a bar line, which close at the bar they lead out of.
        case end
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
        /// shared staff: the ornaments, the fermata, marcato and wedge, the bowing and
        /// technique marks and the fingerings.
        case outside
        /// Outside the staff under the note, whichever part: the inverted fermata, and the
        /// D.C./D.S./Fine words, which Gould puts below the staff of a single-line part
        /// (*Behind Bars*, p. 240).
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
             .strongAccent, .staccatissimo,
             .upbow, .downbow, .open, .snap, .thumb, .plus,
             .segno, .coda:
            return .outside
        case .fingering(let n):
            return (0...5).contains(n) ? .outside : nil
        case .invertedFermata:
            return .below
        case _ where words(for: decoration) != nil, .dacoda:
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
        case .upbow:           return .glyph(.stringsUpBow)
        case .downbow:         return .glyph(.stringsDownBow)
        case .open:            return .glyph(.stringsHarmonic)
        case .snap:            return .glyph(above ? .pluckedSnapPizzicatoAbove : .pluckedSnapPizzicatoBelow)
        case .thumb:           return .glyph(.stringsThumbPosition)
        case .plus:            return .glyph(.pluckedLeftHandPizzicato)
        case .fingering(let n):
            let digits: [SMuFLGlyph] = [.fingering0, .fingering1, .fingering2,
                                        .fingering3, .fingering4, .fingering5]
            return digits.indices.contains(n) ? .glyph(digits[n]) : nil
        case .segno:           return .glyph(.segno)
        case .coda:            return .glyph(.coda)
        case .dacoda:          return .daCoda
        default:               return words(for: decoration).map(Mark.words)
        }
    }

    /// The words a repeat instruction is written out as: Gould's spellings (*Behind Bars*,
    /// pp. 238–239), "Fine" and "al Coda" rather than abcm2ps's "FINE" and the spec's
    /// lower-case "al coda".
    static func words(for decoration: Decoration) -> String? {
        switch decoration {
        case .fine:           return "Fine"
        case .dacapo:         return "D.C."
        case .dacapoAlFine:   return "D.C. al Fine"
        case .dacapoAlCoda:   return "D.C. al Coda"
        case .dalsegno:       return "D.S."
        case .dalsegnoAlFine: return "D.S. al Fine"
        case .dalsegnoAlCoda: return "D.S. al Coda"
        case .dacapoWords:    return "Da Capo"
        default:              return nil
        }
    }

    /// The size the words are set in, in staff spaces: abcm2ps's 16 points (`dacs`) against
    /// its 6-point staff space.
    static let wordsSize = 16.0 / 6.0
    /// How far the words reach over their baseline and under it, in staff spaces: Libertinus
    /// Serif's ascenders (a little over its italic cap height) and descenders.
    static let wordsAscent = 0.7 * wordsSize
    static let wordsDescent = LibertinusSerifMetrics.descenderRatio * wordsSize
    /// Between "Da" and the coda sign after it.
    static let daCodaGap = 0.25
    /// The coda sign after "Da", scaled to stand a little taller than the capitals beside
    /// it, as Gould sets it in "D.C. al ⊕" (*Behind Bars*, p. 239).
    static let daCodaScale = 0.5

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
        var anchor: Anchor = .centre
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
        for decoration in decorations where !decoration.isPause {
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
        case .words:
            return (wordsAscent, wordsDescent)
        case .daCoda:
            let coda = extent(of: .glyph(.coda), above: above, metadata: metadata)
            return (max(wordsAscent, coda.ascent * daCodaScale),
                    max(wordsDescent, coda.descent * daCodaScale))
        }
    }

    // MARK: - On a bar line

    /// The marks written on a bar line (`!segno!|`, `!D.C.!|]`), placed as Gould places them
    /// (*Behind Bars*, p. 240): the segno and coda over the staff, centred on the bar line;
    /// the words under it, ending at the bar line.  Each side stacks outward in the order
    /// written, as the marks on a note do.  The breath, caesura and phrase marks are not
    /// here: they stand in front of the bar line, see ``pause(for:)``.
    static func planBar(_ decorations: [Decoration], metadata: BravuraMetadata) -> Plan {
        var plan = Plan(nextAbove: -staffGap, nextBelow: 4 + staffGap)
        for decoration in decorations where !decoration.isPause {
            guard let mark = mark(for: decoration, above: true) else { continue }
            let above: Bool
            switch mark {
            case .words, .daCoda: above = false
            default:              above = true
            }
            let (ascent, descent) = extent(of: mark, above: above, metadata: metadata)
            if above {
                let baseline = plan.nextAbove - descent
                plan.marks.append(Placed(mark: mark, above: true, baselineY: baseline,
                                         atStem: false, anchor: .centre))
                plan.outerAbove = baseline - ascent
                plan.nextAbove = baseline - ascent - markGap
            } else {
                let baseline = plan.nextBelow + ascent
                plan.marks.append(Placed(mark: mark, above: false, baselineY: baseline,
                                         atStem: false, anchor: .end))
                plan.outerBelow = baseline + descent
                plan.nextBelow = baseline + descent + markGap
            }
        }
        return plan
    }

    // MARK: - Between two notes

    /// A mark set between a note and what follows it, not over or under the note: the
    /// breath mark, the caesura and the phrase marks.
    enum Pause: Equatable {
        /// A glyph whose baseline is at `baselineY`.
        case glyph(SMuFLGlyph, baselineY: Double)
        /// A vertical stroke from `topY` down to `bottomY`.
        case stroke(topY: Double, bottomY: Double)
    }

    /// Where a pause mark stands, in staff spaces down from the top line.
    ///
    /// Gould: "Place the comma and caesura just before a subsequent note or barline …  The
    /// strokes [of the caesura] are placed on the second stave-line down, extending upwards
    /// to the position of a first ledger line above the stave."  The comma stands half a
    /// space over the top line, where abcm2ps sets its breath mark (`stafft + 1`).  The
    /// phrase marks run from there down as far as §4.14 says: the upper part of the staff,
    /// the middle line, three quarters of the way down.
    static func pause(for decoration: Decoration) -> Pause? {
        switch decoration {
        case .breath:       return .glyph(.breathMarkComma, baselineY: -pauseClearance)
        case .caesura:      return .glyph(.caesura, baselineY: 1)
        case .shortPhrase:  return .stroke(topY: -pauseClearance, bottomY: 1)
        case .mediumPhrase: return .stroke(topY: -pauseClearance, bottomY: 2)
        case .longPhrase:   return .stroke(topY: -pauseClearance, bottomY: 3)
        default:            return nil
        }
    }

    /// From the top line to the foot of the breath mark and the top of a phrase mark.
    static let pauseClearance = 0.5

    /// `pause` raised clear of the ledger lines of the note before it, whose highest head is
    /// at staff position `highest` (0 the bottom line, 8 the top): a breath mark stands as
    /// far over the highest ledger line as it would over the staff, as abcm2ps raises its
    /// breath over what the note reaches.  Everything else is left where it is.
    static func raised(_ pause: Pause, overStaffPosition highest: Int?) -> Pause {
        guard case .glyph(.breathMarkComma, let baselineY) = pause,
              let highest, highest >= 10 else { return pause }
        let ledger = highest.isMultiple(of: 2) ? highest : highest - 1
        return .glyph(.breathMarkComma,
                      baselineY: min(baselineY, Double(8 - ledger) / 2 - pauseClearance))
    }
    /// A phrase mark's stroke: abcm2ps's 1.2 points against its 6-point space.
    static let phraseStrokeWidth = 0.2
    /// From a pause mark's right edge to the note or bar line it stands in front of.
    static let pauseGap = 0.4
    /// From a phrase mark written on a bar line to the bar line.
    static let phraseBarGap = 1.0

    /// How wide `pause` is, in staff spaces.
    static func width(of pause: Pause, metadata: BravuraMetadata) -> Double {
        switch pause {
        case .glyph(let glyph, _):
            guard let box = metadata.glyphBBoxes[glyph.rawValue] else { return 1 }
            return box.neX - box.swX
        case .stroke:
            return phraseStrokeWidth
        }
    }

    /// How far over the top line `pause` reaches, in staff spaces.
    static func reachAbove(of pause: Pause, metadata: BravuraMetadata) -> Double {
        switch pause {
        case .glyph(let glyph, let baselineY):
            let top = metadata.glyphBBoxes[glyph.rawValue]?.neY ?? 1
            return max(0, -(baselineY - top))
        case .stroke(let topY, _):
            return max(0, -topY)
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

extension Decoration {
    /// The breath, caesura and phrase marks: set between two notes, never stacked on one.
    var isPause: Bool { DecorationStack.pause(for: self) != nil }
}
