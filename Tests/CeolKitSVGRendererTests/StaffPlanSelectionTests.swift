import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #65: `%%score` / `%%staves` decides which voices are printed and in what order
/// (ABC v2.2 §11.1).
///
/// Selection is asserted through `VoiceSelector` rather than the finished page, because the
/// geometry says how many staves were drawn but not which voice is on which; the end-to-end
/// tests at the bottom cover the staff counts.
@Suite("Staff Plan Selection")
struct StaffPlanSelectionTests {

    // MARK: - Helpers

    /// Runs the selection the renderer runs, on a real parse.
    private func select(_ abc: String)
        -> (voices: [VoiceId], selection: VoiceSelector.Selection, diagnostics: [Diagnostic]) {
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        var diagnostics: [Diagnostic] = []
        let plan = tune.staffPlans.last { $0.effectiveFromStave == 0 }?.plan
        let chosen = VoiceSelector.select(from: tune.voices, plan: plan, into: &diagnostics)
        return (chosen.voices.map(\.id), chosen, diagnostics)
    }

    private func codes(_ diagnostics: [Diagnostic], _ code: DiagnosticCode) -> [Diagnostic] {
        diagnostics.filter { $0.code == code }
    }

    /// Three voices, one bar each, with `directive` above the `K:`.
    ///
    /// Built by line so that the no-directive case does not leave a blank line behind — a
    /// blank line ends the tune, and the tune this returns would be two.
    private func threeVoices(_ directive: String = "") -> String {
        ([
            "X:1",
            "L:1/4",
            directive,
            "V:1", "V:2", "V:3",
            "K:C",
            "V:1", "CDEF|",
            "V:2", "GABc|",
            "V:3", "cdef|"
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func render(_ abc: String) -> (pages: [PageGeometry], diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer().render(score, diagnostics: &diagnostics)
        return (try! SVGGeometry.pages(from: svgs), diagnostics)
    }

    // MARK: - No plan

    @Test("Without a plan the voices keep their declaration order")
    func noPlan() {
        let result = select(threeVoices())
        #expect(result.voices == [.named("1"), .named("2"), .named("3")])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("Without a plan a declared voice the body never writes to is still not printed")
    func noPlanDropsEmptyVoices() {
        let result = select("""
        X:1
        L:1/4
        V:1
        V:2
        K:C
        V:1
        CDEF|
        """)
        #expect(result.voices == [.named("1")])
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: - Selection

    @Test("A plan omitting a voice does not print it, and says so")
    func selectsNamedVoices() {
        let result = select(threeVoices("%%score [1 2]"))
        #expect(result.voices == [.named("1"), .named("2")])

        let omitted = codes(result.diagnostics, .voiceNotInStaffPlan)
        #expect(omitted.count == 1)
        #expect(omitted.first?.message.contains("'3'") == true)
        #expect(omitted.first?.severity == .info)
    }

    @Test("%%staves selects the same way %%score does")
    func stavesSpellingSelects() {
        #expect(select(threeVoices("%%staves [1|2]")).voices == [.named("1"), .named("2")])
    }

    // MARK: - Ordering

    @Test("The plan's order wins over the order the voices were declared in")
    func reordersVoices() {
        #expect(select(threeVoices("%%score [2 1]")).voices == [.named("2"), .named("1")])
    }

    @Test("Reordering carries every voice, not just the ones that moved")
    func reordersAllThree() {
        let result = select(threeVoices("%%score [3 1 2]"))
        #expect(result.voices == [.named("3"), .named("1"), .named("2")])
        #expect(codes(result.diagnostics, .voiceNotInStaffPlan).isEmpty)
    }

    // MARK: - Approximations this phase makes

    @Test("A shared-staff group keeps both voices and puts them on one staff")
    func sharedStaffIsOneStaff() {
        let result = select(threeVoices("%%score (1 2)"))
        #expect(result.voices == [.named("1"), .named("2")])
        #expect(result.selection.staffOfVoice == [0, 0])
        #expect(result.selection.staffCount == 1)
        // Nothing is approximated any more: #76 lays the group out on a shared staff.
        #expect(codes(result.diagnostics, .staffPlanNotFullyApplied).isEmpty)
    }

    @Test("A floating voice is split between the staves on either side of it")
    func floatingVoiceIsSplitBetweenItsNeighbours() {
        let result = select(threeVoices("%%score {1 *2| 3}"))
        // Two staves, and voice 2 twice: once as the lowest part of staff 0 and once as the
        // highest of staff 1 (#80).  Both halves keep the id, because both are voice 2.
        #expect(result.voices == [.named("1"), .named("2"), .named("3"), .named("2")])
        #expect(result.selection.staffOfVoice == [0, 0, 1, 1])
        #expect(result.selection.staffCount == 2)
        // Nothing is approximated any more: the plan is applied as written.
        #expect(codes(result.diagnostics, .staffPlanNotFullyApplied).isEmpty)
    }

    @Test("A floating voice with only one neighbour prints on it, and warns")
    func floatingVoiceWithOneNeighbour() {
        // `*1` is at the top of the plan, so it has a staff below it and none above.
        let result = select(threeVoices("%%score {*1 2| 3}"))
        // It joins staff 0 as its last tenant, so the clef and name that staff draws stay
        // voice 2's — the voice actually written at the top of it.
        #expect(result.voices == [.named("2"), .named("1"), .named("3")])
        #expect(result.selection.staffOfVoice == [0, 0, 1])

        let warnings = codes(result.diagnostics, .staffPlanNotFullyApplied)
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.message.contains("only one") == true)
    }

    @Test("A body plan takes effect from its own stave, without complaint")
    func bodyPlanTakesEffect() {
        let result = render("""
        X:1
        L:1/4
        V:1
        V:2
        K:C
        V:1
        CDEF|
        V:2
        GABc|
        %%score [1]
        V:1
        cdef|
        V:2
        CDEF|
        """)
        // Two staves before the plan, one after — see `StaffPlanRegionTests` for the
        // segmentation this rests on.
        #expect(result.pages.flatMap(\.systems).count == 3)
        #expect(result.diagnostics.filter { $0.code == .staffPlanNotFullyApplied }.isEmpty)
        // Voice 2 still has music the second plan does not print, and §11.1 says so.
        #expect(codes(result.diagnostics, .voiceNotInStaffPlan).count == 1)
    }

    // MARK: - Plans the tune cannot honour

    @Test("A voice the tune does not have is a warning, and the rest of the plan stands")
    func unknownVoiceWarns() {
        let result = select(threeVoices("%%score [1 9 2]"))
        #expect(result.voices == [.named("1"), .named("2")])

        let warnings = codes(result.diagnostics, .staffPlanVoiceNotFound)
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("'9'") == true)
        #expect(warnings.first?.severity == .warning)
    }

    @Test("A voice declared but never written to is skipped without complaint")
    func declaredButEmptyVoiceIsQuiet() {
        let result = select("""
        X:1
        L:1/4
        %%score [1 2]
        V:1
        V:2
        K:C
        V:1
        CDEF|
        """)
        #expect(result.voices == [.named("1")])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A repeated voice is printed once, where it is first named")
    func repeatedVoiceIsPrintedOnce() {
        let result = select(threeVoices("%%score [1 2 1]"))
        #expect(result.voices == [.named("1"), .named("2")])

        let warnings = codes(result.diagnostics, .staffPlanVoiceRepeated)
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("'1'") == true)
    }

    @Test("A plan that selects nothing falls back to the no-plan layout")
    func emptyPlanFallsBack() {
        let result = select(threeVoices("%%score [8 9]"))
        #expect(result.voices == [.named("1"), .named("2"), .named("3")])

        #expect(codes(result.diagnostics, .staffPlanEmpty).count == 1)
        #expect(codes(result.diagnostics, .staffPlanVoiceNotFound).count == 2)
        // The fallback prints every voice, so reporting any as omitted would be a lie.
        #expect(codes(result.diagnostics, .voiceNotInStaffPlan).isEmpty)
    }

    // MARK: - End to end

    @Test("%%score [1 2] on a three-voice tune renders two staves")
    func twoStavesOnThePage() {
        #expect(render(threeVoices("%%score [1 2]")).pages.flatMap(\.systems).count == 2)
    }

    @Test("%%score (1 2) renders one staff carrying both voices")
    func sharedStaffDrawsOne() {
        #expect(render(threeVoices("%%score (1 2)")).pages.flatMap(\.systems).count == 1)
    }

    /// Two voices on known source lines.  The system's scroll-sync anchor is taken from the
    /// first printed voice, so it names which voice the plan put on top.
    private let twoVoicesOnKnownLines = [
        "X:1",          // 1
        "L:1/4",        // 2
        "%%score PLAN", // 3
        "V:1",          // 4
        "V:2",          // 5
        "K:C",          // 6
        "V:1",          // 7
        "CDEF|",        // 8
        "V:2",          // 9
        "cdef|"         // 10
    ]

    private func anchorLine(plan: String) -> Int? {
        let abc = twoVoicesOnKnownLines.map { $0.replacing("PLAN", with: plan) }.joined(separator: "\n")
        return render(abc).pages.flatMap(\.systems).first?.abcLine
    }

    @Test("The voice the plan names first is the one drawn on the top staff")
    func planOrderReachesThePage() {
        // Voice 1's music is on line 8, voice 2's on line 10.
        #expect(anchorLine(plan: "[1 2]") == 8)
        #expect(anchorLine(plan: "[2 1]") == 10)
    }

    @Test("A tune with no plan renders every voice it did before")
    func noPlanRendersEveryVoice() {
        let result = render(threeVoices())
        #expect(result.pages.flatMap(\.systems).count == 3)
        #expect(result.diagnostics.isEmpty)
    }
}
