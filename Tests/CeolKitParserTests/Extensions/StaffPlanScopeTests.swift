// Issue #157: which tunes a %%score / %%staves written outside any tune governs.
// Parser and model only — nothing here asserts about rendering.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Staff Plan Scope")
struct StaffPlanScopeTests {

    // MARK: - Helpers

    /// Every tune's plans, each as the staves it resolves to, so a test can name a plan
    /// without rebuilding the tree.  A tune with no plan is an empty element, not a gap.
    private func plansPerTune(_ abc: String) -> [[[[VoiceId]]]] {
        parse(abc).score.tunes.map { tune in
            tune.staffPlans.map { $0.plan.layout.staves }
        }
    }

    private func inapplicable(_ abc: String) -> [Diagnostic] {
        parse(abc).score.diagnostics.filter { $0.code == .staffPlanNotApplicableToTune }
    }

    /// `count` tunes, each with voices T and B and one line of music apiece, with `preamble`
    /// above the first and `between` written in the gap ahead of tune `beforeTune`.
    private func tunes(
        _ count: Int,
        preamble: String = "",
        between: String = "",
        beforeTune: Int = 1,
        headers: [Int: String] = [:]
    ) -> String {
        var lines: [String] = preamble.isEmpty ? [] : [preamble]
        for index in 0..<count {
            if !between.isEmpty && index == beforeTune { lines.append(between) }
            lines += ["X:\(index + 1)", "L:1/4"]
            if let header = headers[index] { lines.append(header) }
            lines += ["V:T", "V:B", "K:C", "V:T", "CDEF|", "V:B", "GABc|", ""]
        }
        return lines.joined(separator: "\n")
    }

    private let braced: [[VoiceId]] = [[.named("T"), .named("B")]]
    private let separate: [[VoiceId]] = [[.named("T")], [.named("B")]]

    // MARK: - A plan in the file header

    @Test("A file-header plan governs every tune, not only the first")
    func fileHeaderPlanGovernsEveryTune() {
        let plans = plansPerTune(tunes(3, preamble: "%%score (T B)"))
        #expect(plans == [[braced], [braced], [braced]])
    }

    @Test("A tune stating its own plan uses it; the tunes around it keep the file header's")
    func tuneHeaderOverridesTheFileHeader() {
        let plans = plansPerTune(
            tunes(3, preamble: "%%score (T B)", headers: [1: "%%score [T B]"]))
        // Tune 2 carries both, in source order, and the later one wins downstream.
        #expect(plans == [[braced], [braced, separate], [braced]])
    }

    @Test("A file-header plan naming voices a tune does not have does not govern it")
    func planNamingAbsentVoicesIsNotApplied() throws {
        let abc = """
        %%score (T B)
        X:1
        L:1/4
        V:T
        V:B
        K:C
        V:T
        CDEF|
        V:B
        GABc|

        X:2
        L:1/4
        V:1
        V:2
        K:C
        V:1
        CDEF|
        V:2
        GABc|
        """
        #expect(plansPerTune(abc) == [[braced], []])

        let diagnostics = inapplicable(abc)
        try #require(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .info)
        #expect(diagnostics[0].source.line == 1)
        #expect(diagnostics[0].message.contains("'T', 'B'"))
    }

    @Test("A tune the plan fits draws no diagnostic")
    func applicablePlanIsQuiet() {
        #expect(inapplicable(tunes(2, preamble: "%%score (T B)")).isEmpty)
    }

    @Test("A tune stating its own plan is not diagnosed over one it never uses")
    func overriddenPlanIsNotDiagnosed() {
        let abc = """
        %%score (T B)
        X:1
        L:1/4
        %%score [1 2]
        V:1
        V:2
        K:C
        V:1
        CDEF|
        V:2
        GABc|
        """
        #expect(inapplicable(abc).isEmpty)
    }

    // MARK: - A plan in the gap between two tunes

    @Test("A plan written between two tunes governs the tunes after it, not the ones before")
    func gapPlanGovernsWhatFollowsIt() {
        let plans = plansPerTune(tunes(3, between: "%%score (T B)", beforeTune: 1))
        #expect(plans == [[], [braced], [braced]])
    }

    @Test("A plan in a later gap replaces the one in force, from that point on")
    func laterGapPlanReplacesTheEarlierOne() {
        let abc = tunes(3, preamble: "%%score (T B)", between: "%%score [T B]", beforeTune: 2)
        #expect(plansPerTune(abc) == [[braced], [braced], [separate]])
    }

    // MARK: - Regression

    @Test("A plan in a tune body still opens a region part-way through that tune alone")
    func bodyPlanStillResetsPartWayThrough() throws {
        let abc = """
        %%score (T B)
        X:1
        L:1/4
        V:T
        V:B
        K:C
        V:T
        CDEF|
        V:B
        GABc|
        %%score [T B]
        V:T
        CDEF|
        V:B
        GABc|

        X:2
        L:1/4
        V:T
        V:B
        K:C
        V:T
        CDEF|
        V:B
        GABc|
        """
        let tunes = parse(abc).score.tunes
        try #require(tunes.count == 2)
        #expect(tunes[0].staffPlans.map(\.effectiveFromStave) == [0, 1])
        #expect(tunes[0].staffPlans.map { $0.plan.layout.staves } == [braced, separate])
        // The body plan belongs to the tune it was written in; tune 2 opens on the file's.
        #expect(tunes[1].staffPlans.map(\.effectiveFromStave) == [0])
        #expect(tunes[1].staffPlans.map { $0.plan.layout.staves } == [braced])
    }
}
