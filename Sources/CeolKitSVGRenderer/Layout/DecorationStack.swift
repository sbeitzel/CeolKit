import CeolKitModel

/// The marks drawn over (or under) a note clear of everything the note itself reaches —
/// its heads, its stem or beam, a grace group in front of it — and stacked one beyond
/// another in the order they were written (issue #264).
///
/// These are abcm2ps's `d_upstaff` decorations: `y_get` finds how high the note's column
/// already reaches, never lower than just outside the staff, the mark is set there and the
/// column raised by its height for the next.  `THe` therefore draws the trill nearest the
/// note and the fermata beyond it, as written.
///
/// The emitter places the marks and ``VerticalLayoutEngine`` reserves room for them, and
/// both measure them here so the two agree.
enum DecorationStack {

    /// One mark of the stack.
    enum Mark: Equatable {
        /// A SMuFL glyph, drawn centred over the notehead.
        case glyph(SMuFLGlyph)
        /// An Irish roll: the small arc abcm2ps draws for `~` (its `cpu`).  SMuFL has no
        /// glyph for it, so it is drawn as a path.
        case roll
    }

    /// Which side of the staff a mark goes on.
    enum Side {
        /// Over the staff — or under it for a part whose stems go down on a shared staff,
        /// as abcm2ps puts its lower voice's ornaments below.
        case stemSide
        /// Under the staff, whichever voice: the inverted fermata.
        case below
    }

    /// The mark `decoration` stacks, or `nil` for a decoration drawn some other way (or, as
    /// yet, not at all).
    static func mark(for decoration: Decoration, below: Bool) -> Mark? {
        switch decoration {
        case .trill:           return .glyph(.ornamentTrill)
        case .mordent:         return .glyph(.ornamentMordent)
        case .pralltriller:    return .glyph(.ornamentShortTrill)
        case .turn:            return .glyph(.ornamentTurn)
        case .invertedTurn:    return .glyph(.ornamentTurnInverted)
        case .roll:            return .roll
        case .fermata:         return .glyph(below ? .fermataBelow : .fermataAbove)
        case .invertedFermata: return .glyph(.fermataBelow)
        default:               return nil
        }
    }

    /// The side `decoration` stacks on, for a decoration ``mark(for:below:)`` draws.
    static func side(of decoration: Decoration) -> Side {
        decoration == .invertedFermata ? .below : .stemSide
    }

    /// The marks of `decorations` on one side, in the order they are stacked outward.
    static func marks(of decorations: [Decoration], side: Side, flipped: Bool) -> [Mark] {
        decorations.compactMap { decoration in
            guard self.side(of: decoration) == side else { return nil }
            return mark(for: decoration, below: side == .below || flipped)
        }
    }

    // MARK: - Metrics (staff spaces)

    /// Space between the note's own reach and the first mark.
    static let noteGap = 0.5
    /// The least distance from the outer staff line to the first mark.
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

    /// How far `mark` extends from its baseline, outward and inward, in staff spaces.
    /// A glyph's box comes from its metadata.
    static func extent(of mark: Mark, metadata: BravuraMetadata) -> (ascent: Double, descent: Double) {
        switch mark {
        case .glyph(let glyph):
            guard let box = metadata.glyphBBoxes[glyph.rawValue] else { return (1.0, 0) }
            return (box.neY, -box.swY)
        case .roll:
            return (rollHeight, 0)
        }
    }

    /// How far the marks reach beyond the first mark's base: the room the stack takes.
    static func height(of marks: [Mark], metadata: BravuraMetadata) -> Double {
        guard !marks.isEmpty else { return 0 }
        let total = marks.reduce(0.0) { sum, mark in
            let e = extent(of: mark, metadata: metadata)
            return sum + e.ascent + e.descent
        }
        return total + Double(marks.count - 1) * markGap
    }
}

extension DecorationStack {
    /// How far one period of `wiggleTrill` advances, in staff spaces: Bravura's advance
    /// width, which its metadata does not carry.  Periods set this far apart join up.
    static let wiggleAdvance = 0.948
}
