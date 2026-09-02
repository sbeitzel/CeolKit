// %%score / %%staves conformance tests (ABC v2.2 §11.1).
// Parser and model only — nothing here asserts about rendering.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Staff Plan Directives")
struct StaffPlanDirectiveTests {

    // MARK: - Helpers

    /// The staff plan attached to the first tune, or `nil` if the directive was dropped.
    private func staffPlan(_ abc: String) -> StaffPlan? {
        guard let tune = parse(abc).score.firstTune else { return nil }
        for scoped in tune.directives {
            if case .staffPlan(let plan) = scoped.directive { return plan }
        }
        return nil
    }

    private func staffPlanDiagnostics(_ abc: String) -> [Diagnostic] {
        parse(abc).score.diagnostics.filter { $0.code == .invalidStaffPlan }
    }

    /// Wraps a directive in the smallest tune that parses.
    private func tune(_ directive: String) -> String {
        """
        X:1
        T:Test
        M:4/4
        L:1/4
        \(directive)
        K:C
        CDEF|
        """
    }

    private func voice(_ node: StaffPlanNode?) -> StaffPlanVoice? {
        if case .voice(let v) = node { return v }
        return nil
    }

    private func branch(_ node: StaffPlanNode?) -> StaffPlanBranch? {
        switch node {
        case .shared(let b), .brace(let b), .bracket(let b): return b
        default: return nil
        }
    }

    // MARK: - Accepted plans

    @Test("%%score [1 2 3] is a bracket of three separately barred voices")
    func canzonetta() {
        let plan = staffPlan(tune("%%score [1 2 3]"))
        let root = try! #require(plan?.root)
        #expect(root.tail.isEmpty)

        guard case .bracket(let inner) = root.head else {
            Issue.record("root node is not a bracket: \(root.head)")
            return
        }
        #expect(inner.nodes.count == 3)
        #expect(inner.nodes.compactMap(voice).map(\.id) == [.named("1"), .named("2"), .named("3")])
        #expect(inner.tail.map(\.joint) == [.separate, .separate])
        #expect(inner.nodes.compactMap(voice).allSatisfy { !$0.isFloating })
    }

    @Test("%%score (T1 T2) (B1 B2) is two shared-staff groups at the root")
    func zochartiLoch() {
        let plan = staffPlan(tune("%%score (T1 T2) (B1 B2)"))
        let root = try! #require(plan?.root)
        #expect(root.tail.count == 1)
        #expect(root.tail.map(\.joint) == [.separate])

        guard case .shared(let tenors) = root.head,
              case .shared(let basses) = root.tail[0].node else {
            Issue.record("root is not two shared groups: \(root)")
            return
        }
        #expect(tenors.nodes.compactMap(voice).map(\.id) == [.named("T1"), .named("T2")])
        #expect(basses.nodes.compactMap(voice).map(\.id) == [.named("B1"), .named("B2")])
        #expect(tenors.tail.map(\.joint) == [.separate])
        #expect(basses.tail.map(\.joint) == [.separate])
    }

    @Test("%%score [{Vln1 | Vln2} | Vla | Vc | DB] nests a brace inside a bracket")
    func stringQuintet() {
        let plan = staffPlan(tune("%%score [{Vln1 | Vln2} | Vla | Vc | DB]"))
        let root = try! #require(plan?.root)

        guard case .bracket(let outer) = root.head else {
            Issue.record("root node is not a bracket: \(root.head)")
            return
        }
        #expect(outer.nodes.count == 4)
        #expect(outer.tail.map(\.joint) == [.continuedBarline, .continuedBarline, .continuedBarline])
        #expect(outer.nodes.dropFirst().compactMap(voice).map(\.id)
                == [.named("Vla"), .named("Vc"), .named("DB")])

        guard case .brace(let violins) = outer.head else {
            Issue.record("first node is not a brace: \(outer.head)")
            return
        }
        #expect(violins.nodes.compactMap(voice).map(\.id) == [.named("Vln1"), .named("Vln2")])
        #expect(violins.tail.map(\.joint) == [.continuedBarline])
    }

    @Test("%%score {RH *M| LH} marks only M as floating")
    func floatingVoice() {
        let plan = staffPlan(tune("%%score {RH *M| LH}"))
        let root = try! #require(plan?.root)

        guard case .brace(let inner) = root.head else {
            Issue.record("root node is not a brace: \(root.head)")
            return
        }
        let voices = inner.nodes.compactMap(voice)
        #expect(voices.map(\.id) == [.named("RH"), .named("M"), .named("LH")])
        #expect(voices.map(\.isFloating) == [false, true, false])
        #expect(inner.tail.map(\.joint) == [.separate, .continuedBarline])
    }

    @Test("A floating voice's source range covers the '*' and the id")
    func floatingVoiceSourceRange() {
        let abc = tune("%%score {RH *M| LH}")
        let plan = staffPlan(abc)
        let root = try! #require(plan?.root)
        guard case .brace(let inner) = root.head, let floater = voice(inner.nodes[1]) else {
            Issue.record("expected a floating voice at index 1")
            return
        }
        // "%%score {RH *M| LH}" — '*' is the 13th character, i.e. column 13 (1-based).
        #expect(floater.source.column == 13)
        #expect(floater.source.length == 2)
    }

    // MARK: - %%staves inverts the sense of '|'

    @Test("%%staves [S|A|T|B] and %%score [S A T B] describe the same plan")
    func stavesInvertsJoints() {
        let fromStaves = staffPlan(tune("%%staves [S|A|T|B]"))
        let fromScore = staffPlan(tune("%%score [S A T B]"))
        let staves = try! #require(fromStaves)
        let score = try! #require(fromScore)
        #expect(staves == score)
        #expect(staves.hashValue == score.hashValue)
    }

    @Test("%%staves without '|' continues the bar lines")
    func stavesAdjacencyContinuesBarlines() {
        let fromStaves = staffPlan(tune("%%staves [S A]"))
        let fromScore = staffPlan(tune("%%score [S|A]"))
        let staves = try! #require(fromStaves)
        let score = try! #require(fromScore)
        #expect(staves == score)

        guard case .bracket(let inner) = staves.root.head else {
            Issue.record("root node is not a bracket: \(staves.root.head)")
            return
        }
        #expect(inner.tail.map(\.joint) == [.continuedBarline])
    }

    @Test("Plans that differ in joints are not equal")
    func differingJointsAreUnequal() {
        let separate = try! #require(staffPlan(tune("%%score [S A]")))
        let joined = try! #require(staffPlan(tune("%%score [S|A]")))
        #expect(separate != joined)
    }

    @Test("Plans that differ in nesting are not equal")
    func differingNestingAreUnequal() {
        let bracket = try! #require(staffPlan(tune("%%score [S A]")))
        let brace = try! #require(staffPlan(tune("%%score {S A}")))
        #expect(bracket != brace)
    }

    // MARK: - Placement

    @Test("%%score in the file preamble attaches to the tune")
    func preamble() {
        let abc = """
        %%score [1 2]
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        #expect(staffPlan(abc) != nil)
        #expect(staffPlanDiagnostics(abc).isEmpty)
    }

    @Test("%%score in the tune body attaches and is not reported as unknown")
    func body() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        %%score [1 2]
        CDEF|
        """
        #expect(staffPlan(abc) != nil)
        let unknown = parse(abc).score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    // MARK: - Rejected plans

    @Test("An unclosed delimiter drops the directive", arguments: [
        "%%score [1 2",
        "%%score {1 2",
        "%%score (1 2",
    ])
    func unclosed(_ directive: String) {
        let abc = tune(directive)
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("A mismatched delimiter drops the directive")
    func mismatchedDelimiter() {
        let abc = tune("%%score [1 2}")
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("A closing delimiter with nothing open drops the directive")
    func strayCloser() {
        let abc = tune("%%score 1 2]")
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("An empty group drops the directive", arguments: [
        "%%score ()",
        "%%score []",
        "%%score {}",
        "%%score [1 ()]",
    ])
    func emptyGroup(_ directive: String) {
        let abc = tune(directive)
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("An empty payload drops the directive")
    func emptyPayload() {
        let abc = tune("%%score")
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("A stray '|' drops the directive", arguments: [
        "%%score [|1 2]",
        "%%score [1 2|]",
        "%%score [1 || 2]",
        "%%score |1 2",
        "%%score 1 2|",
    ])
    func strayBar(_ directive: String) {
        let abc = tune(directive)
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("'*' on something that is not a bare voice drops the directive", arguments: [
        "%%score *(1 2)",
        "%%score *[1 2]",
        "%%score {1 *}",
        "%%score 1 *",
    ])
    func floatingNonVoice(_ directive: String) {
        let abc = tune(directive)
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("An illegal character in a voice id drops the directive")
    func illegalVoiceIdCharacter() {
        let abc = tune("%%score [1 + 2]")
        #expect(staffPlan(abc) == nil)
        #expect(staffPlanDiagnostics(abc).count == 1)
    }

    @Test("A rejected plan still yields a tune with music")
    func recovery() {
        let abc = tune("%%score [1 2")
        let result = parse(abc)
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        #expect(!measures.isEmpty)
    }

    @Test("The diagnostic points at the offending character")
    func diagnosticPosition() {
        // "%%score [1 + 2]" — '+' is the 12th character, i.e. column 12 (1-based).
        let diagnostics = staffPlanDiagnostics(tune("%%score [1 + 2]"))
        let first = try! #require(diagnostics.first)
        #expect(first.source.column == 12)
        #expect(first.severity == .warning)
    }
}
