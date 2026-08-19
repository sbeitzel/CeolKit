// Where a %%score / %%staves takes effect (ABC v2.2 §11.1).
// Parser and model only — nothing here asserts about rendering.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Staff Plan Position")
struct StaffPlanPositionTests {

    // MARK: - Helpers

    private func staffPlans(_ abc: String) -> [StaffPlanChange] {
        parse(abc).score.firstTune?.staffPlans ?? []
    }

    private func snapDiagnostics(_ abc: String) -> [Diagnostic] {
        parse(abc).score.diagnostics.filter { $0.code == .staffPlanSnappedToStave }
    }

    /// The staves a plan resolves to, so a test can name a plan without rebuilding the tree.
    private func staves(_ change: StaffPlanChange) -> [[VoiceId]] {
        change.plan.layout.staves
    }

    // MARK: - Plans written before any music

    @Test("A tune with no plan has no changes")
    func noPlan() {
        #expect(staffPlans("""
        X:1
        L:1/4
        K:C
        CDEF|
        """).isEmpty)
    }

    @Test("A header %%score governs from the first stave")
    func headerPlan() throws {
        let changes = staffPlans("""
        X:1
        L:1/4
        %%score [1 2]
        K:C
        CDEF|
        """)
        let change = try #require(changes.first)
        #expect(changes.count == 1)
        #expect(change.effectiveFromStave == 0)
        #expect(staves(change) == [[.named("1")], [.named("2")]])
    }

    @Test("A file-preamble %%score governs from the first stave, ahead of the header's")
    func preambleAndHeaderPlans() throws {
        let changes = staffPlans("""
        %%score [1 2]
        X:1
        L:1/4
        %%score (1 2)
        K:C
        CDEF|
        """)
        try #require(changes.count == 2)
        #expect(changes.map(\.effectiveFromStave) == [0, 0])
        // Source order: the preamble plan first, the header plan — which wins — second.
        #expect(staves(changes[0]) == [[.named("1")], [.named("2")]])
        #expect(staves(changes[1]) == [[.named("1"), .named("2")]])
    }

    // MARK: - Plans written in the body

    @Test("A body %%score after the third source line governs from stave 3")
    func bodyPlanAfterThreeStaves() throws {
        let changes = staffPlans("""
        X:1
        L:1/4
        K:C
        CDEF|
        GABc|
        defg|
        %%score [1 2]
        cBAG|
        """)
        #expect(changes.count == 1)
        #expect(try #require(changes.first).effectiveFromStave == 3)
    }

    @Test("Two body %%score directives yield two changes in source order")
    func twoBodyPlans() throws {
        let changes = staffPlans("""
        X:1
        L:1/4
        K:C
        CDEF|
        %%score [1 2 3]
        GABc|
        defg|
        %%score [1 2]
        cBAG|
        """)
        try #require(changes.count == 2)
        #expect(changes.map(\.effectiveFromStave) == [1, 3])
        #expect(staves(changes[0]).count == 3)
        #expect(staves(changes[1]).count == 2)
    }

    @Test("A header plan and a body plan are both recorded, in source order")
    func headerThenBody() {
        let changes = staffPlans("""
        X:1
        L:1/4
        %%score [1 2 3]
        K:C
        CDEF|
        GABc|
        %%score [1 2]
        defg|
        """)
        #expect(changes.map(\.effectiveFromStave) == [0, 2])
    }

    @Test("%%staves is positioned the same way %%score is")
    func stavesSpelling() {
        let changes = staffPlans("""
        X:1
        L:1/4
        K:C
        CDEF|
        %%staves [1|2]
        GABc|
        """)
        #expect(changes.map(\.effectiveFromStave) == [1])
    }

    @Test("A stave index counts systems, not source lines, in a multi-voice tune")
    func multiVoiceCountsSystems() {
        let abc = """
        X:1
        L:1/4
        V:1
        V:2
        K:C
        V:1
        CDEF|
        V:2
        C2E2|
        %%score (1 2)
        V:1
        GABc|
        V:2
        G2B2|
        """
        // Two source lines of music above the directive, but only one finished system.
        #expect(staffPlans(abc).map(\.effectiveFromStave) == [1])
        #expect(snapDiagnostics(abc).isEmpty)
    }

    @Test("A malformed body payload records no change")
    func malformedBodyPlan() {
        let changes = staffPlans("""
        X:1
        L:1/4
        K:C
        CDEF|
        %%score [1 2
        GABc|
        """)
        #expect(changes.isEmpty)
    }

    // MARK: - Snapping

    @Test("A %%score inside a stave snaps to the enclosing stave and warns")
    func snapsToEnclosingStave() throws {
        let abc = """
        X:1
        L:1/4
        I:linebreak $
        K:C
        CDEF|$GABc|
        %%score [1 2]
        defg|
        """
        let changes = staffPlans(abc)
        // The `$` ended stave 0; the stave holding GABc| runs on past the end of the source
        // line, so the plan lands inside stave 1 and governs the whole of it.
        #expect(changes.map(\.effectiveFromStave) == [1])

        let diags = snapDiagnostics(abc)
        #expect(diags.count == 1)
        #expect(try #require(diags.first).severity == .warning)
    }

    @Test("With line breaks off, a body %%score snaps back to the tune's one stave")
    func snapsWithLineBreaksOff() {
        let abc = """
        X:1
        L:1/4
        I:linebreak <none>
        K:C
        CDEF|
        %%score [1 2]
        GABc|
        """
        #expect(staffPlans(abc).map(\.effectiveFromStave) == [0])
        #expect(snapDiagnostics(abc).count == 1)
    }

    @Test("A %%score at a stave boundary does not warn")
    func boundaryDoesNotWarn() {
        #expect(snapDiagnostics("""
        X:1
        L:1/4
        K:C
        CDEF|
        %%score [1 2]
        GABc|
        """).isEmpty)
    }

    @Test("A plan before any music does not warn")
    func headerDoesNotWarn() {
        #expect(snapDiagnostics("""
        X:1
        L:1/4
        %%score [1 2]
        K:C
        CDEF|
        """).isEmpty)
    }

    // MARK: - The directive list is unchanged

    @Test("Positioned plans are still in tune.directives, where the renderer reads them")
    func directivesStillCarryThePlans() throws {
        let tune = parse("""
        X:1
        L:1/4
        %%score [1 2 3]
        K:C
        CDEF|
        %%score [1 2]
        GABc|
        """).score.firstTune
        let plans = (tune?.directives ?? []).compactMap { scoped -> StaffPlan? in
            if case .staffPlan(let plan) = scoped.directive { return plan }
            return nil
        }
        try #require(plans.count == 2)
        #expect(plans[0].layout.staves.count == 3)
        #expect(plans[1].layout.staves.count == 2)
    }
}
