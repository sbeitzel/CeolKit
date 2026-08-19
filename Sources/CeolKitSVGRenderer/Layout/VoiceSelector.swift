import CeolKitModel

/// Pass 1¼: decides which of a tune's voices are printed, and in what order, from the plan
/// a `%%score` / `%%staves` gave (ABC v2.2 §11.1).
///
/// §11.1: "Any voices appearing in the tune body will only be printed if it is mentioned in
/// the score directive."  A plan therefore both *filters* and *orders*, and its order wins
/// over the order the voices were declared in.
///
/// **One staff per voice, always.**  This pass runs ahead of the shared-staff work, so the
/// voices of a `( … )` group each get a staff of their own and a floating `*V` gets one at
/// the position it was written; both say so in a `staffPlanNotFullyApplied` diagnostic.
/// That is strictly better than ignoring the directive — the right voices print in the right
/// order, and only the vertical grouping is missing — and it keeps every voice the plan
/// names on the page, which silently dropping the ones this pass cannot group would not.
///
/// **It also translates the plan's grouping into printed staff indices.**  `StaffPlanLayout`
/// counts staves in the *plan*, and the four approximations above mean those are not the
/// staves that reach the page.  This is the only pass that sees both numberings at once, so
/// it is the one that has to do the translation; see ``Selection/grouping``.
enum VoiceSelector {

    /// What the plan asked for, in the terms the rest of the layout works in.
    struct Selection {
        /// The voices to print, top to bottom — one staff each.
        let voices: [Voice]
        /// The plan's spans and bar-line joins over ``voices``, or `nil` when there was no
        /// plan to take them from, or the plan selected nothing and was fallen back from.
        let grouping: StaffGrouping?
    }

    /// - Parameters:
    ///   - voices: every voice of the tune, including ones the body never wrote to.  Those
    ///     are in the model precisely so a plan can name them, so naming one is not an error.
    ///   - plan: the staff plan in effect, or `nil` when the tune has none.
    /// - Returns: the voices to print, top to bottom.  Never contains a voice with no music:
    ///   the aligner would pad it with invisible rests on every line and warn that the voices
    ///   disagree, drawing a staff of silence the source never asked for.
    static func select(
        from voices: [Voice],
        plan: StaffPlan?,
        into diagnostics: inout [Diagnostic]
    ) -> Selection {
        let printable = voices.filter { !$0.isEmpty }
        guard let plan else { return Selection(voices: printable, grouping: nil) }

        let layout = plan.layout
        let byId = Dictionary(voices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var printed: [Voice] = []
        var seen: Set<VoiceId> = []
        // Printed staff indices contributed by each staff of the plan, in order.  Empty for a
        // plan staff whose every voice was dropped; more than one where a `( … )` shared staff
        // was expanded to a staff per voice.
        var printedByPlanStaff = [[Int]](repeating: [], count: layout.staves.count)
        for (id, planStaff) in order(of: layout) {
            guard seen.insert(id).inserted else {
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .staffPlanVoiceRepeated,
                    message: "staff plan names voice \(label(id)) more than once; "
                           + "it is printed once, where it is first named",
                    source: plan.source))
                continue
            }
            guard let voice = byId[id] else {
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .staffPlanVoiceNotFound,
                    message: "staff plan names voice \(label(id)), which this tune does not have",
                    source: plan.source))
                continue
            }
            // Named, declared, and never written to: §11.1 prints the voices that appear in
            // the tune body, and this one does not appear there.  Not worth a diagnostic —
            // the plan is right and the body simply has nothing to say.
            guard !voice.isEmpty else { continue }
            if let planStaff { printedByPlanStaff[planStaff].append(printed.count) }
            printed.append(voice)
        }

        guard !printed.isEmpty else {
            // Reporting each voice as unprinted would be a lie: the fallback prints them all.
            diagnostics.append(Diagnostic(
                severity: .warning, code: .staffPlanEmpty,
                message: "staff plan selects none of this tune's voices; "
                       + "laying the tune out as though it had no plan",
                source: plan.source))
            return Selection(voices: printable, grouping: nil)
        }

        diagnostics += omissions(from: printable, namedBy: layout, plan: plan)
        diagnostics += approximations(of: layout, printedBy: printed, plan: plan)
        return Selection(voices: printed,
                         grouping: grouping(of: layout, printedBy: printedByPlanStaff))
    }

    // MARK: - Order

    /// The plan's voices, top to bottom, one entry per staff this pass will draw.
    ///
    /// A floating voice has no staff in the layout, so it is placed after the staff it floats
    /// below — or first, where the plan gives it nothing above.  That is where the author
    /// wrote it, and it is the position `#80` will start from when it assigns such a voice
    /// per note.
    ///
    /// The staff index is the plan's, and `nil` for a floating voice — it belongs to no
    /// staff of the plan, so no span or joint is stated over it.
    private static func order(of layout: StaffPlanLayout) -> [(id: VoiceId, planStaff: Int?)] {
        let floatingByStaffAbove = Dictionary(grouping: layout.floating, by: \.above)
        var ordered = (floatingByStaffAbove[nil] ?? []).map { (id: $0.id, planStaff: Int?.none) }
        for (index, staff) in layout.staves.enumerated() {
            ordered += staff.map { (id: $0, planStaff: Int?.some(index)) }
            ordered += (floatingByStaffAbove[index] ?? []).map { (id: $0.id, planStaff: Int?.none) }
        }
        return ordered
    }

    // MARK: - Grouping

    /// The plan's spans and joints, re-expressed over the staves that will actually print.
    ///
    /// Returned even when it is empty of both: a plan that groups nothing still says the
    /// bar lines are *not* to run between its staves, which is not the same as having no
    /// plan at all.
    private static func grouping(
        of layout: StaffPlanLayout,
        printedBy printedByPlanStaff: [[Int]]
    ) -> StaffGrouping {
        // A span covers whichever printed staves its plan staves produced.  Taking the
        // extremes rather than the union also pulls in a floating voice that was written
        // inside the span, which is where its author put it.
        let spans = layout.spans.compactMap { span -> StaffGrouping.Span? in
            let covered = span.staves.flatMap { printedByPlanStaff[$0] }
            guard let first = covered.min(), let last = covered.max() else { return nil }
            return StaffGrouping.Span(bracket: span.bracket, staves: first...last,
                                      depth: span.depth)
        }

        var joins: Set<Int> = []
        for above in layout.barlineJoins {
            // A joint whose staff above or below printed nothing joins nothing.  Where a
            // floating voice sits between the two, every boundary it introduces is joined,
            // so the continuation reads as the one stroke the plan asked for.
            guard let top = printedByPlanStaff[above].last,
                  let bottom = printedByPlanStaff[above + 1].first else { continue }
            joins.formUnion(top..<bottom)
        }
        // §11.1 says nothing about the boundary between two staves that are one staff in the
        // source: a `( … )` group the shared-staff work has not landed for yet.  Continuing
        // the bar line through it is the closest drawing to the single staff it stands in for.
        for printed in printedByPlanStaff where printed.count > 1 {
            joins.formUnion(printed.dropLast())
        }

        return StaffGrouping(spans: spans, barlineJoins: joins)
    }

    // MARK: - Diagnostics

    /// Voices the body wrote to that the plan leaves out, and so §11.1 does not print.
    private static func omissions(
        from printable: [Voice],
        namedBy layout: StaffPlanLayout,
        plan: StaffPlan
    ) -> [Diagnostic] {
        let named = Set(layout.staves.flatMap { $0 } + layout.floating.map(\.id))
        return printable.filter { !named.contains($0.id) }.map { voice in
            Diagnostic(
                severity: .info, code: .voiceNotInStaffPlan,
                message: "voice \(label(voice.id)) has music in the tune body but is not in "
                       + "the staff plan, so it is not printed",
                source: plan.source)
        }
    }

    /// The parts of the plan this pass draws differently from what it asks for.
    private static func approximations(
        of layout: StaffPlanLayout,
        printedBy printed: [Voice],
        plan: StaffPlan
    ) -> [Diagnostic] {
        let ids = Set(printed.map(\.id))
        var result: [Diagnostic] = []

        for staff in layout.staves {
            let sharing = staff.filter { ids.contains($0) }
            guard sharing.count > 1 else { continue }
            result.append(Diagnostic(
                severity: .info, code: .staffPlanNotFullyApplied,
                message: "voices \(list(sharing)) share one staff in the plan; "
                       + "each is drawn on a staff of its own for now",
                source: plan.source))
        }

        for floating in layout.floating where ids.contains(floating.id) {
            result.append(Diagnostic(
                severity: .info, code: .staffPlanNotFullyApplied,
                message: "voice \(label(floating.id)) floats between staves in the plan; "
                       + "it is drawn on a staff of its own for now",
                source: plan.source))
        }

        return result
    }

    // MARK: - Naming

    private static func label(_ id: VoiceId) -> String {
        switch id {
        case .named(let name): return "'\(name)'"
        case .all:             return "'*'"
        }
    }

    private static func list(_ ids: [VoiceId]) -> String {
        ids.map(label).joined(separator: ", ")
    }
}
