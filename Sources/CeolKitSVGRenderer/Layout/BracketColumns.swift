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
        let tipWidth = metadata.glyphBBoxes["bracketTop"].map { $0.width } ?? 1.876
        widths = (0...deepest).map { depth in
            ((depth == 0 ? tipWidth : Clearance.subBracketHook) + Clearance.column) * staffSize
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
