/// The columns of space to the left of a system's staves that its braces and brackets
/// occupy, and where each one's spine stands.
///
/// The indent and the furniture that fills it are one calculation deliberately.  The width
/// reserved here is subtracted from the music twice over — the line breaker packs into what
/// is left, and the justifier stretches into it — while the layout engine spends it by
/// moving the staves right and the emitter draws into what that vacates.  Four callers
/// agreeing by construction is the only way the bracket lands inside the page margin and
/// the last note still lands on it.
///
/// One column per nesting depth, outermost leftmost, so `[{A B} C]` reads as a bracket
/// standing left of a brace rather than the two overlapping.
struct BracketColumns: Sendable {

    /// Sizes in staff spaces.  The tip widths come from the face's own bounding boxes;
    /// these are the clearances around them, which no metadata states.
    private enum Clearance {
        /// Space between a column's furniture and whatever stands to its right — the next
        /// column in, or the staff itself.
        static let column = 0.4
        /// How far a nested span's end hooks reach towards the staff.  A sub-bracket has no
        /// glyph of its own in SMuFL: it is a thin spine with short serifs at each end.
        static let subBracketHook = 0.5
        /// The widest a brace is ever drawn.
        ///
        /// Bravura draws its brace 0.32 spaces wide at a natural height of 3.988 — the
        /// proportions of a brace over *one* staff.  Stretched to a piano system's 11
        /// spaces on the vertical axis alone it comes out four times too thin to read as a
        /// brace at all, so the arms grow with it; past a staff space of width they stop,
        /// or a brace over five staves is a slab.  abcm2ps settles on a constant width too,
        /// and by the same reasoning from the other end: its brace is drawn at system
        /// height and only ever compressed, leaving it a shade heavier than this at about
        /// 1.5 spaces.
        static let braceMaxWidth = 1.0
    }

    /// The spans that are actually drawn, and so the ones that get to reserve space.
    let spans: [StaffGrouping.Span]
    /// Width of the column at each depth, outermost (depth 0) first.  Empty when nothing
    /// is drawn, which is the no-plan case and every single-staff system.
    let widths: [Double]

    /// Total space reserved to the left of the staves.  Zero unless something is drawn.
    var indent: Double { widths.reduce(0, +) }

    /// - Parameters:
    ///   - grouping: the system's plan-derived spans, or `nil` where it has no plan.
    ///   - staffCount: staves in the system, used to drop a span that reaches past them.
    init(grouping: StaffGrouping?, staffCount: Int,
         metadata: BravuraMetadata, staffSize: Double) {
        spans = Self.drawable(grouping?.spans ?? [], staffCount: staffCount)
        guard let deepest = spans.map(\.depth).max() else {
            widths = []
            return
        }
        // One column per depth, wide enough for the widest thing standing in it: one depth
        // can hold both kinds at once — `[{A B} [C D]]` puts a brace and a sub-bracket in
        // the same column — and they are nothing like the same width.
        var ink: [Int: Double] = [:]
        for span in spans {
            ink[span.depth] = max(ink[span.depth] ?? 0, Self.inkWidth(of: span, metadata: metadata))
        }
        widths = (0...deepest).map { depth in
            // A depth with nothing left in it reserves nothing: `drawable` can empty an
            // outer depth while an inner span survives, and a column no furniture stands
            // in would just be a gap.
            guard let width = ink[depth] else { return 0 }
            return (width + Clearance.column) * staffSize
        }
    }

    /// How far right of its column's left edge a span's furniture reaches, in staff spaces.
    ///
    /// Read off the face's own bounding box where a glyph is drawn — measured from the
    /// glyph origin, which is what the emitter places at the column's left edge, so the
    /// reservation covers the ink and not just its width.
    private static func inkWidth(of span: StaffGrouping.Span,
                                 metadata: BravuraMetadata) -> Double {
        switch span.bracket {
        // The brace grows with its span, so what is reserved is the widest it can get.  A
        // shorter one leaves a little air rather than a differently indented system: the
        // indent is a property of the plan, and a plan does not change between systems of
        // one region while the staves it covers may.
        case .brace:
            guard let box = metadata.glyphBBoxes["brace"] else { return 0.328 }
            return box.neX * Self.braceWidthScale(box: box)
        case .bracket:
            guard span.depth == 0 else { return Clearance.subBracketHook }
            guard let box = metadata.glyphBBoxes["bracketTop"] else { return 1.876 }
            return box.neX
        }
    }

    /// Absolute x of the left edge of the spine drawn for a span at `depth`, given the x the
    /// staves start at.
    func spineX(depth: Int, staffLeftX: Double) -> Double {
        staffLeftX - widths[min(depth, widths.count - 1)...].reduce(0, +)
    }

    /// How far a nested span's end hooks reach towards the staff, at `staffSize`.  The
    /// emitter draws them; this is where their length is stated, so the column reserved for
    /// them and the hooks drawn into it stay the same size.
    static func subBracketHookLength(staffSize: Double) -> Double {
        Clearance.subBracketHook * staffSize
    }

    /// The factors a brace is scaled by to reach `height` points: uniform until its arms
    /// are ``Clearance/braceMaxWidth`` wide, vertical-only after that.
    ///
    /// `nil` where there is nothing to draw — a span of no height, or a face whose brace
    /// has none.  Stated here, next to the space reserved for it, so that the column and
    /// the glyph standing in it cannot disagree about how wide a brace gets.
    static func braceScale(height: Double, metadata: BravuraMetadata,
                           staffSize: Double) -> (x: Double, y: Double)? {
        let box = metadata.glyphBBoxes["brace"]
        let naturalHeight = (box?.height ?? 3.988) * staffSize
        guard naturalHeight > 0, height > 0 else { return nil }
        let yScale = height / naturalHeight
        let cap = box.map(braceWidthScale) ?? Clearance.braceMaxWidth / 0.32
        return (min(yScale, cap), yScale)
    }

    /// The largest horizontal factor a brace is drawn at, for a face whose brace has the
    /// given box: the one that makes its arms exactly ``Clearance/braceMaxWidth`` wide.
    private static func braceWidthScale(box: BravuraMetadata.BoundingBox) -> Double {
        guard box.width > 0 else { return 1 }
        return Clearance.braceMaxWidth / box.width
    }

    /// The spans worth drawing furniture for, of the ones the plan states.
    ///
    /// A span reaching past the last staff is dropped rather than clamped: a grouping is
    /// built over the very staves of the region it is stamped on, so one that does not fit
    /// did not come from this system's selection, and a bracket drawn to a staff that is
    /// not there would be worse than none.
    ///
    /// A span over a single staff is dropped for a different reason: the furniture that
    /// joins staves is drawn by the system's group, and a one-staff system has none.
    /// Reserving space for a bracket nothing would draw is what leaves a gap on the page.
    private static func drawable(_ spans: [StaffGrouping.Span],
                                 staffCount: Int) -> [StaffGrouping.Span] {
        spans.filter { $0.staves.count > 1 && $0.staves.upperBound < staffCount }
    }
}
