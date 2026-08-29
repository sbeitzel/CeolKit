import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)
private let config     = SVGRenderConfig()
private let metadata   = try! BravuraMetadata.load()

private func emptyMeasure(line: Int = 0) -> Measure {
    Measure(openingBar: nil, events: [], closingBar: dummyBar, endingNumber: nil,
            source: SourceRange(file: nil, byteOffset: 0, length: 0, line: line, column: 0))
}

private func sizedMeasure(width: Double = 100) -> SizedMeasure {
    SizedMeasure(measure: emptyMeasure(), naturalWidth: width, eventOffsets: [])
}

private func justifiedSystem(isLast: Bool = false) -> JustifiedSystem {
    JustifiedSystem(measures: [JustifiedMeasure(source: sizedMeasure(), finalWidth: 100,
                                                eventOffsets: [])],
                    isLastSystem: isLast, sourceForced: false)
}

/// Issue #67: the plan's brace/bracket spans and continued bar-line boundaries reach the
/// layout, expressed in the indices of the staves that actually print (ABC v2.2 §11.1).
///
/// Nothing draws them yet — #68 and #70 do that — so these tests assert the data and the
/// existing golden tests assert that the page is unchanged.
@Suite("Staff Span Threading")
struct StaffSpanThreadingTests {

    // MARK: - Selection

    /// The grouping the renderer would hand the line breaker, from a real parse.
    private func selectGrouping(_ abc: String) -> StaffGrouping? {
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        var diagnostics: [Diagnostic] = []
        let plan = tune.staffPlans.last { $0.effectiveFromStave == 0 }?.plan
        return VoiceSelector.select(from: tune.voices, plan: plan, into: &diagnostics).grouping
    }

    /// Three voices, one bar each, with `directive` above the `K:`.  A voice listed in
    /// `silent` is declared but never written to, so the plan may name it and it still
    /// does not print.
    private func threeVoices(_ directive: String = "", silent: Set<String> = []) -> String {
        let body = ["1", "2", "3"].filter { !silent.contains($0) }
                                  .flatMap { ["V:\($0)", "CDEF|"] }
        return (["X:1", "L:1/4", directive, "V:1", "V:2", "V:3", "K:C"] + body)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    @Test("A tune with no plan has no grouping at all")
    func noPlanNoGrouping() {
        #expect(selectGrouping(threeVoices()) == nil)
    }

    @Test("%%score [1 2] is one bracket over both staves, and no joins")
    func bracketOverTwoStaves() throws {
        let grouping = try #require(selectGrouping(threeVoices("%%score [1 2]")))
        #expect(grouping.spans == [StaffGrouping.Span(bracket: .bracket, staves: 0...1, depth: 0)])
        #expect(grouping.barlineJoins.isEmpty)
    }

    @Test("%%score [{1 | 2} | 3] nests a brace inside a bracket and joins both boundaries")
    func nestedBraceInsideBracket() throws {
        let grouping = try #require(selectGrouping(threeVoices("%%score [{1 | 2} | 3]")))
        #expect(grouping.spans == [
            StaffGrouping.Span(bracket: .bracket, staves: 0...2, depth: 0),
            StaffGrouping.Span(bracket: .brace, staves: 0...1, depth: 1),
        ])
        #expect(grouping.barlineJoins == [0, 1])
    }

    @Test("A plan that only orders the voices groups none of them, and says so")
    func planWithoutDelimitersGroupsNothing() throws {
        // Not the same as having no plan: the bar lines are not to run between these staves.
        let grouping = try #require(selectGrouping(threeVoices("%%score 2 1")))
        #expect(grouping.spans.isEmpty)
        #expect(grouping.barlineJoins.isEmpty)
    }

    @Test("A span shrinks to the staves that print when a voice it covers has no music")
    func spanShrinksPastAVoiceWithNoMusic() throws {
        // The plan names three voices; the middle one is declared but never written to, so
        // §11.1 does not print it and the bracket covers the two staves that are left.
        let grouping = try #require(selectGrouping(threeVoices("%%score [1 2 3]", silent: ["2"])))
        #expect(grouping.spans == [StaffGrouping.Span(bracket: .bracket, staves: 0...1, depth: 0)])
    }

    @Test("A join reaches through the staff a floating voice was given")
    func joinReachesThroughAFloatingVoice() throws {
        // `*2` has no staff in the plan, but is drawn on one of its own for now, so the
        // join written between staves 1 and 3 spans two printed boundaries, not one.
        let grouping = try #require(selectGrouping(threeVoices("%%score {1 *2| 3}")))
        #expect(grouping.spans == [StaffGrouping.Span(bracket: .brace, staves: 0...2, depth: 0)])
        #expect(grouping.barlineJoins == [0, 1])
    }

    @Test("A shared staff is one staff, so the span over it covers one")
    func sharedStaffIsOneStaff() throws {
        // `(1 2)` is one staff in the source and one on the page (#76), so the bracket
        // covers two staves and there is no boundary inside the group to join.
        let grouping = try #require(selectGrouping(threeVoices("%%score [(1 2) 3]")))
        #expect(grouping.spans == [StaffGrouping.Span(bracket: .bracket, staves: 0...1, depth: 0)])
        #expect(grouping.barlineJoins.isEmpty)
    }

    @Test("A plan that selects no voice is fallen back from, grouping and all")
    func fallbackHasNoGrouping() {
        #expect(selectGrouping(threeVoices("%%score [8 9]")) == nil)
    }

    // MARK: - Threading through the breaker and justifier

    @Test("Every system of a tune carries the tune's grouping, the last one included")
    func groupingSurvivesBreakingAndJustification() {
        let grouping = StaffGrouping(
            spans: [StaffGrouping.Span(bracket: .bracket, staves: 0...1, depth: 0)],
            barlineJoins: [0])
        // Five 90 pt measures over a 300 pt line: more than one system, so the last-system
        // rebuild inside the breaker is exercised too.
        let voiceLines = (0..<2).map { _ in
            LineBreaker.VoiceLine(measures: (0..<5).map { _ in sizedMeasure(width: 90) })
        }
        let groups = LineBreaker().breakIntoGroups(
            voiceLines, breaks: Array(repeating: nil, count: 5), usableWidth: 300,
            grouping: grouping)
        #expect(groups.count > 1)
        #expect(groups.allSatisfy { $0.grouping?.spans == grouping.spans })
        #expect(groups.allSatisfy { $0.grouping?.barlineJoins == grouping.barlineJoins })

        let justified = Justifier().justifyGroups(groups, usableWidth: 300, justifyLastSystem: false)
        #expect(justified.allSatisfy { $0.grouping?.spans == grouping.spans })
    }

    // MARK: - Placement

    private func layout(_ grouping: StaffGrouping?, staves: Int) -> [ResolvedSystem] {
        let systems = (0..<staves).map { justifiedSystem(isLast: $0 == staves - 1) }
        let block = TuneBlock(systemGroups: [JustifiedSystemGroup(staves: systems,
                                                                  grouping: grouping)])
        return VerticalLayoutEngine(config: config, metadata: metadata)
            .layout([block]).pages[0].systems
    }

    @Test("A span is placed from the top line of its first staff to the bottom line of its last")
    func spansAreResolvedToAbsoluteY() throws {
        let systems = layout(StaffGrouping(spans: [
            StaffGrouping.Span(bracket: .bracket, staves: 0...2, depth: 0),
            StaffGrouping.Span(bracket: .brace, staves: 0...1, depth: 1),
        ], barlineJoins: [1]), staves: 3)

        // Both spans start on the top staff, which is the staff that draws group furniture.
        let leader = try #require(systems[0].staffGroup)
        #expect(leader.isGroupLeader)
        #expect(leader.spans.map(\.bracket) == [.bracket, .brace])
        #expect(leader.spans.map(\.depth) == [0, 1])

        let staffHeight = 4.0 * config.staffSize
        let topLine = systems[0].origin.y + systems[0].staffOrigin
        #expect(leader.spans[0].topY == topLine)
        #expect(leader.spans[1].topY == topLine)
        // The bracket reaches the foot of the group; the brace stops at the middle staff.
        #expect(abs(leader.spans[0].bottomY - leader.bottomY) < 1e-9)
        #expect(abs(leader.spans[1].bottomY
                    - (systems[1].origin.y + systems[1].staffOrigin + staffHeight)) < 1e-9)

        // A span is listed once, on the staff it starts at — not on every staff it covers.
        let middle = try #require(systems[1].staffGroup)
        let bottom = try #require(systems[2].staffGroup)
        #expect(middle.spans.isEmpty)
        #expect(bottom.spans.isEmpty)
    }

    @Test("Only the boundaries the plan joins continue")
    func onlyPlannedBoundariesContinue() throws {
        let systems = layout(StaffGrouping(spans: [], barlineJoins: [1]), staves: 3)
        let flags = try systems.map { try #require($0.staffGroup).continuesBarlineBelow }
        #expect(flags == [false, true, false])
    }

    @Test("With no plan every boundary continues, as it did before plans existed")
    func withoutAPlanEveryBoundaryContinues() throws {
        let systems = layout(nil, staves: 3)
        let flags = try systems.map { try #require($0.staffGroup).continuesBarlineBelow }
        #expect(flags == [true, true, false])
        #expect(systems.allSatisfy { $0.staffGroup?.spans.isEmpty ?? true })
    }
}
