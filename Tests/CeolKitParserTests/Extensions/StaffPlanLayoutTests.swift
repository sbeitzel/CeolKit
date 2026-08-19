// StaffPlanLayout — the %%score / %%staves tree flattened to the staff table the layout
// engine consumes (ABC v2.2 §11.1).  Model only: nothing here asserts about rendering.
//
// The plans are built by parsing, because that is the only way a StaffPlan is ever made
// and it keeps each case readable as the directive an author would actually write.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Staff Plan Layout")
struct StaffPlanLayoutTests {

    // MARK: - Helpers

    /// The layout of the staff plan attached to the first tune of the smallest tune that
    /// parses, or `nil` if the directive was dropped.
    private func flatten(_ directive: String) -> StaffPlanLayout? {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        \(directive)
        K:C
        CDEF|
        """
        guard let tune = parse(abc).score.firstTune else { return nil }
        for scoped in tune.directives {
            if case .staffPlan(let plan) = scoped.directive { return plan.layout }
        }
        return nil
    }

    private func named(_ ids: String...) -> [VoiceId] {
        ids.map { .named($0) }
    }

    // MARK: - Staves

    @Test("%%score [1 2 3] is three staves under one bracket")
    func canzonetta() throws {
        let layout = try #require(flatten("%%score [1 2 3]"))
        #expect(layout.staves == [named("1"), named("2"), named("3")])
        #expect(layout.spans == [
            StaffPlanLayout.Span(bracket: .bracket, staves: 0...2, depth: 0),
        ])
        #expect(layout.barlineJoins.isEmpty)
        #expect(layout.floating.isEmpty)
    }

    @Test("%%score (T1 T2) (B1 B2) is two shared staves and no spans")
    func zochartiLoch() throws {
        let layout = try #require(flatten("%%score (T1 T2) (B1 B2)"))
        #expect(layout.staves == [named("T1", "T2"), named("B1", "B2")])
        #expect(layout.spans.isEmpty)
        #expect(layout.barlineJoins.isEmpty)
        #expect(layout.floating.isEmpty)
    }

    @Test("A bare voice list is one staff each")
    func bareVoices() throws {
        let layout = try #require(flatten("%%score S A T B"))
        #expect(layout.staves == [named("S"), named("A"), named("T"), named("B")])
        #expect(layout.spans.isEmpty)
        #expect(layout.barlineJoins.isEmpty)
    }

    // MARK: - Spans

    @Test("%%score [{Vln1 | Vln2} | Vla | Vc | DB] nests a brace inside a bracket")
    func stringQuintet() throws {
        let layout = try #require(flatten("%%score [{Vln1 | Vln2} | Vla | Vc | DB]"))
        #expect(layout.staves == [
            named("Vln1"), named("Vln2"), named("Vla"), named("Vc"), named("DB"),
        ])
        // Outermost first.
        #expect(layout.spans == [
            StaffPlanLayout.Span(bracket: .bracket, staves: 0...4, depth: 0),
            StaffPlanLayout.Span(bracket: .brace, staves: 0...1, depth: 1),
        ])
        // Every sibling boundary in the plan is written with '|', so bar lines run
        // unbroken from the first violin staff to the double bass.
        #expect(layout.barlineJoins == [0, 1, 2, 3])
        #expect(layout.floating.isEmpty)
    }

    @Test("%%score Solo [(S A) (T B)] {RH | (LH1 LH2)} — the standard's own example")
    func specExample() throws {
        let layout = try #require(flatten("%%score Solo  [(S A) (T B)]  {RH | (LH1 LH2)}"))
        #expect(layout.staves == [
            named("Solo"), named("S", "A"), named("T", "B"), named("RH"), named("LH1", "LH2"),
        ])
        #expect(layout.spans == [
            StaffPlanLayout.Span(bracket: .bracket, staves: 1...2, depth: 0),
            StaffPlanLayout.Span(bracket: .brace, staves: 3...4, depth: 0),
        ])
        #expect(layout.barlineJoins == [3])
        #expect(layout.floating.isEmpty)
    }

    @Test("Sibling groups at the same nesting are both depth 0")
    func siblingGroupsShareDepth() throws {
        let layout = try #require(flatten("%%score [1 2] [3 4]"))
        #expect(layout.spans.map(\.depth) == [0, 0])
        #expect(layout.spans.map(\.staves) == [0...1, 2...3])
    }

    @Test("Depth counts grouping delimiters, however deeply they nest")
    func nestedDepth() throws {
        let layout = try #require(flatten("%%score [{[1 2] 3} 4]"))
        #expect(layout.staves.count == 4)
        #expect(layout.spans == [
            StaffPlanLayout.Span(bracket: .bracket, staves: 0...3, depth: 0),
            StaffPlanLayout.Span(bracket: .brace, staves: 0...2, depth: 1),
            StaffPlanLayout.Span(bracket: .bracket, staves: 0...1, depth: 2),
        ])
    }

    @Test("A group that covers no staff draws no span")
    func spanOverNothing() throws {
        let layout = try #require(flatten("%%score RH {*M} LH"))
        #expect(layout.staves == [named("RH"), named("LH")])
        #expect(layout.spans.isEmpty)
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: 0, below: 1),
        ])
    }

    @Test("Delimiters nested inside a shared group draw no span")
    func sharedGroupSwallowsDelimiters() throws {
        let layout = try #require(flatten("%%score ([A B] C)"))
        #expect(layout.staves == [named("A", "B", "C")])
        #expect(layout.spans.isEmpty)
    }

    // MARK: - Bar-line joins

    @Test("'|' joins the staff above the boundary to the one below it")
    func joinsAreIndexedByTheStaffAbove() throws {
        let layout = try #require(flatten("%%score [1 2|3 4|5]"))
        #expect(layout.barlineJoins == [1, 3])
    }

    @Test("A '|' across a group boundary joins the last staff of one to the first of the next")
    func joinsCrossGroupBoundaries() throws {
        let layout = try #require(flatten("%%score [{1 2} | {3 4}]"))
        #expect(layout.staves.count == 4)
        #expect(layout.barlineJoins == [1])
    }

    @Test("%%staves inverts '|', and the two spellings flatten identically")
    func stavesInvertsJoints() throws {
        let fromStaves = try #require(flatten("%%staves [S|A|T|B]"))
        let fromScore = try #require(flatten("%%score [S A T B]"))
        #expect(fromStaves == fromScore)
        #expect(fromStaves.barlineJoins.isEmpty)

        let joined = try #require(flatten("%%staves [S A T B]"))
        #expect(joined.barlineJoins == [0, 1, 2])
    }

    // MARK: - Floating voices

    @Test("%%score {RH *M| LH} floats M between the two staves it is written between")
    func floatingVoice() throws {
        let layout = try #require(flatten("%%score {RH *M| LH}"))
        #expect(layout.staves == [named("RH"), named("LH")])
        #expect(layout.spans == [
            StaffPlanLayout.Span(bracket: .brace, staves: 0...1, depth: 0),
        ])
        #expect(layout.barlineJoins == [0])
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: 0, below: 1),
        ])
    }

    @Test("%%score {(RH1 RH2) *M| (LH1 LH2)} floats between two shared staves")
    func floatingBetweenSharedStaves() throws {
        let layout = try #require(flatten("%%score {(RH1 RH2) *M| (LH1 LH2)}"))
        #expect(layout.staves == [named("RH1", "RH2"), named("LH1", "LH2")])
        #expect(layout.barlineJoins == [0])
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: 0, below: 1),
        ])
    }

    @Test("A floating voice at the top of the plan has no staff above it")
    func floatingAtTop() throws {
        let layout = try #require(flatten("%%score {*M RH LH}"))
        #expect(layout.staves == [named("RH"), named("LH")])
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: nil, below: 0),
        ])
    }

    @Test("A floating voice at the bottom of the plan has no staff below it")
    func floatingAtBottom() throws {
        let layout = try #require(flatten("%%score {RH LH *M}"))
        #expect(layout.staves == [named("RH"), named("LH")])
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: 1, below: nil),
        ])
    }

    @Test("The joint written after a floating voice governs the boundary it straddles")
    func jointAfterFloatingWins() throws {
        // The joint before '*M' would join RH to a staff M does not have, so it is
        // discarded; the one after it settles the RH/LH boundary.
        let joined = try #require(flatten("%%score {RH *M| LH}"))
        #expect(joined.barlineJoins == [0])

        let separate = try #require(flatten("%%score {RH| *M LH}"))
        #expect(separate.barlineJoins.isEmpty)

        // Which means %%staves, where '|' has the opposite sense, inverts cleanly.
        let inverted = try #require(flatten("%%staves {RH *M| LH}"))
        #expect(inverted.barlineJoins.isEmpty)
        #expect(inverted.floating == joined.floating)
    }

    @Test("Two floating voices in a row both name the same neighbours")
    func consecutiveFloatingVoices() throws {
        let layout = try #require(flatten("%%score {RH *M *N| LH}"))
        #expect(layout.staves == [named("RH"), named("LH")])
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: 0, below: 1),
            StaffPlanLayout.FloatingVoice(id: .named("N"), above: 0, below: 1),
        ])
    }

    @Test("A '*' inside a shared group marks nothing — the voice shares the staff")
    func floatingInsideSharedGroup() throws {
        let layout = try #require(flatten("%%score (A *B) C"))
        #expect(layout.staves == [named("A", "B"), named("C")])
        #expect(layout.floating.isEmpty)
    }

    // MARK: - Degenerate plans

    @Test("A plan of one voice is one staff and nothing else")
    func singleVoice() throws {
        let layout = try #require(flatten("%%score 1"))
        #expect(layout.staves == [named("1")])
        #expect(layout.spans.isEmpty)
        #expect(layout.barlineJoins.isEmpty)
        #expect(layout.floating.isEmpty)
    }

    @Test("A plan of nothing but a floating voice has no staves at all")
    func onlyAFloatingVoice() throws {
        let layout = try #require(flatten("%%score *M"))
        #expect(layout.staves.isEmpty)
        #expect(layout.spans.isEmpty)
        #expect(layout.floating == [
            StaffPlanLayout.FloatingVoice(id: .named("M"), above: nil, below: nil),
        ])
    }
}
