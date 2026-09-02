import CeolKitModel

/// Pass 1¼: decides which of a tune's voices are printed, and in what order, from the plan
/// a `%%score` / `%%staves` gave (ABC v2.2 §11.1).
///
/// §11.1: "Any voices appearing in the tune body will only be printed if it is mentioned in
/// the score directive."  A plan therefore both *filters* and *orders*, and its order wins
/// over the order the voices were declared in.
///
/// **A `( … )` group is one staff.**  Its voices come back as several entries of ``voices``
/// mapped by ``Selection/staffOfVoice`` onto a single printed staff, which the driver hands
/// to ``SharedStaffMerger`` to lay out on a common onset grid.
///
/// **A floating `*V` is two voices by the time this pass is done.**  It has no staff of its
/// own; ``FloatingVoiceSplitter`` cuts it along the split ``FloatingVoiceAssigner`` decides
/// and hands each half to the staff on its side, as that staff's last tenant.  Everything
/// downstream sees two ordinary voices sharing two ordinary staves.  Where the plan leaves it
/// only one neighbour there is no split to make, and it becomes an ordinary tenant of that
/// staff with a `staffPlanNotFullyApplied` warning to say so.
///
/// **An `&` overlay is a voice too, by the time this pass is done.**  ``OverlayExpander``
/// gives every `&` layer (§7.4) a place on the staff of the voice that wrote it, directly
/// under it, so a staff with overlays is a shared staff like any other.  This is the last
/// pass that adds a voice to a staff, and it does it after the plan has been resolved: an
/// overlay is not something a `%%score` can name, place or leave out.
///
/// **It also translates the plan's grouping into printed staff indices.**  `StaffPlanLayout`
/// counts staves in the *plan*, and a dropped voice or a floating one means those are not the
/// staves that reach the page.  This is the only pass that sees both numberings at once, so
/// it is the one that has to do the translation; see ``Selection/grouping``.
enum VoiceSelector {

    /// What the plan asked for, in the terms the rest of the layout works in.
    struct Selection {
        /// The voices to print, top to bottom.
        let voices: [Voice]
        /// Which printed staff each of ``voices`` is drawn on, parallel to it.  Two voices
        /// share an entry exactly when the plan put them in one `( … )` group; otherwise
        /// this is `[0, 1, 2, …]` and a staff is a voice, as it always was.
        let staffOfVoice: [Int]
        /// The plan's spans and bar-line joins over the *printed staves*, or `nil` when there
        /// was no plan to take them from, or the plan selected nothing and was fallen back from.
        let grouping: StaffGrouping?

        /// How many staves will be drawn.
        var staffCount: Int { (staffOfVoice.max() ?? -1) + 1 }

        /// The voices on each printed staff, top to bottom.
        var voicesByStaff: [[Int]] {
            (0..<staffCount).map { staff in voices.indices.filter { staffOfVoice[$0] == staff } }
        }

        init(voices: [Voice], staffOfVoice: [Int], grouping: StaffGrouping?) {
            self.voices = voices
            self.staffOfVoice = staffOfVoice
            self.grouping = grouping
        }
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
        guard let plan else { return selection(of: printable.map { [$0] }, grouping: nil) }

        let layout = plan.layout
        let byId = Dictionary(voices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Pass one: which of the plan's voices print at all.  A floating voice's neighbours
        // are staves of the *plan*, and a plan staff only becomes a printed one once
        // something written on it survives — so the two numberings are resolved separately,
        // and in that order.
        var accepted: [(voice: Voice, placement: Placement)] = []
        var seen: Set<VoiceId> = []
        for (id, placement) in order(of: layout) {
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
            accepted.append((voice, placement))
        }

        // Pass two: the printed staff each staff of the plan turned into.  Absent for a plan
        // staff whose every voice was dropped; shared by every voice of a `( … )` group,
        // which is what makes the group one staff.
        var staffForPlanStaff: [Int: Int] = [:]
        var staffed: [[Voice]] = []
        for (voice, placement) in accepted {
            guard case .staff(let planStaff) = placement else { continue }
            if let staff = staffForPlanStaff[planStaff] {
                staffed[staff].append(voice)
            } else {
                staffForPlanStaff[planStaff] = staffed.count
                staffed.append([voice])
            }
        }

        // Pass three: each floating voice, cut in two and handed to the staves on either side
        // of it (#80).  A half joins its staff *last*: the clef, key and name a staff draws
        // are those of the voice written at the top of it, and a voice that floats between
        // two staves is at the top of neither.
        for (voice, placement) in accepted {
            guard case .floating(let abovePlan, let belowPlan) = placement else { continue }
            let above = abovePlan.flatMap { staffForPlanStaff[$0] }
            let below = belowPlan.flatMap { staffForPlanStaff[$0] }
            switch (above, below) {
            case (let above?, let below?):
                let split = FloatingVoiceAssigner.split(
                    middle: voice.properties.middleNote,
                    above: staffed[above][0].properties.clef,
                    below: staffed[below][0].properties.clef)
                let halves = FloatingVoiceSplitter.split(voice, at: split)
                staffed[above].append(halves.above)
                staffed[below].append(halves.below)

            case (let only?, nil), (nil, let only?):
                // §11.1 floats a voice *between* two groups, and this one has one neighbour:
                // either it was written at an end of the plan, or the staff on its other side
                // printed nothing.  There is no choice left to make, so it becomes an
                // ordinary tenant of the staff it does have — dropping the music instead
                // would lose what the author wrote to save a decision nobody needs.
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .staffPlanNotFullyApplied,
                    message: "voice \(label(voice.id)) floats, but the plan leaves it only one "
                           + "neighbouring staff; it is printed on that staff throughout",
                    source: plan.source))
                staffed[only].append(voice)

            case (nil, nil):
                // No neighbour at all — `%%score {*M}`, or a plan whose other staves all
                // dropped out.  It gets a staff of its own, at the bottom, because there is
                // nothing left for it to be positioned relative to.
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .staffPlanNotFullyApplied,
                    message: "voice \(label(voice.id)) floats, but the plan gives it no "
                           + "neighbouring staff at all; it is printed on a staff of its own",
                    source: plan.source))
                staffed.append([voice])
            }
        }

        // Printed staff indices contributed by each staff of the plan: at most one now, and
        // none where every voice of a plan staff was dropped.
        let printedByPlanStaff = layout.staves.indices.map { staffForPlanStaff[$0].map { [$0] } ?? [] }

        guard !staffed.isEmpty else {
            // Reporting each voice as unprinted would be a lie: the fallback prints them all.
            diagnostics.append(Diagnostic(
                severity: .warning, code: .staffPlanEmpty,
                message: "staff plan selects none of this tune's voices; "
                       + "laying the tune out as though it had no plan",
                source: plan.source))
            return selection(of: printable.map { [$0] }, grouping: nil)
        }

        diagnostics += omissions(from: printable, namedBy: layout, plan: plan)
        return selection(of: staffed, grouping: grouping(of: layout, printedBy: printedByPlanStaff))
    }

    /// The selection the staves add up to, with each voice's `&` overlays given their place
    /// on the staff beneath it (§7.4).
    private static func selection(of staffed: [[Voice]], grouping: StaffGrouping?) -> Selection {
        let expanded = staffed.map(OverlayExpander.expand)
        return Selection(
            voices: expanded.flatMap { $0 },
            staffOfVoice: expanded.enumerated().flatMap {
                [Int](repeating: $0.offset, count: $0.element.count)
            },
            grouping: grouping)
    }

    // MARK: - Order

    /// Where the plan puts one voice.
    private enum Placement {
        /// An index into ``StaffPlanLayout/staves``.
        case staff(Int)
        /// A `*V`, with the plan staves on either side of it — either `nil` where the plan
        /// has none there.
        case floating(above: Int?, below: Int?)
    }

    /// The plan's voices, top to bottom, in the order they were written.
    ///
    /// A floating voice has no staff in the layout, so it appears after the staff it floats
    /// below — or first, where the plan gives it nothing above.  That is where the author
    /// wrote it, and it is where the reader of a diagnostic about it will look.
    private static func order(of layout: StaffPlanLayout) -> [(id: VoiceId, placement: Placement)] {
        let floatingByStaffAbove = Dictionary(grouping: layout.floating, by: \.above)
        func floats(below staff: Int?) -> [(id: VoiceId, placement: Placement)] {
            (floatingByStaffAbove[staff] ?? []).map {
                (id: $0.id, placement: Placement.floating(above: $0.above, below: $0.below))
            }
        }
        var ordered = floats(below: nil)
        for (index, staff) in layout.staves.enumerated() {
            ordered += staff.map { (id: $0, placement: Placement.staff(index)) }
            ordered += floats(below: index)
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

    // MARK: - Naming

    private static func label(_ id: VoiceId) -> String {
        switch id {
        case .named(let name): return "'\(name)'"
        case .all:             return "'*'"
        }
    }

}
