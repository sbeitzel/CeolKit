import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #69: a `%%score` in the tune body changes the set of printed voices, so the number
/// of staves differs between systems (ABC v2.2 §11.1).  The renderer runs its whole
/// align → size → break block once per *plan region* and concatenates the results.
@Suite("Staff Plan Regions")
struct StaffPlanRegionTests {

    // MARK: - Helpers

    private func tune(_ abc: String) -> Tune {
        CeolKitParser().parse(abc, options: .default).score.tunes[0]
    }

    private func render(_ abc: String) -> (pages: [PageGeometry], diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer().render(score, diagnostics: &diagnostics)
        return (try! SVGGeometry.pages(from: svgs), diagnostics)
    }

    /// The number of staves in each system group, in page order.
    ///
    /// The vertical layout stamps the group's source line on every staff of it, so a run of
    /// staves reporting the same line is one group.  Sound for these fixtures, where every
    /// source line fits on one system and no two consecutive groups come from one line.
    private func stavesPerSystem(_ abc: String) -> [Int] {
        let systems = render(abc).pages.flatMap(\.systems)
        return systems.reduce(into: [(line: Int?, count: Int)]()) { runs, system in
            if runs.last?.line == system.abcLine { runs[runs.count - 1].count += 1 }
            else { runs.append((system.abcLine, 1)) }
        }.map(\.count)
    }

    private func anchorLines(_ abc: String) -> [Int] {
        render(abc).pages.flatMap(\.systems).compactMap(\.abcLine)
    }

    /// Three voices with `header` above the `K:`, one line each per line-set, and `body`
    /// written between the first and second line-set.
    private func threeVoices(header: String, body: String = "") -> String {
        ([
            "X:1", "L:1/4", header,
            "V:1", "V:2", "V:3", "K:C",
            "V:1", "CDEF|", "V:2", "GABc|", "V:3", "cdef|",
            body,
            "V:1", "CDEF|", "V:2", "GABc|", "V:3", "cdef|"
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Segmentation

    @Test("A tune with no plan is one region over every stave, holding the tune's own voices")
    func noPlanIsOneRegion() {
        let parsed = tune(threeVoices(header: ""))
        let regions = PlanRegions.segment(parsed)
        #expect(regions.count == 1)
        #expect(regions[0].plan == nil)
        #expect(regions[0].staves == 0..<2)
        #expect(regions[0].voices.map(\.staves.count) == parsed.voices.map(\.staves.count))
    }

    @Test("A header plan is one region: nothing about the tune changes part-way through")
    func headerPlanIsOneRegion() {
        let regions = PlanRegions.segment(tune(threeVoices(header: "%%score [1 2]")))
        #expect(regions.count == 1)
        #expect(regions[0].plan != nil)
        #expect(regions[0].staves == 0..<2)
    }

    @Test("A preamble plan and a header plan both govern from stave 0, and stay one region")
    func twoPlansAtStaveZeroAreOneRegion() {
        // Both reach the tune with `effectiveFromStave: 0`; the later one wins, as it does
        // for every other directive, and neither opens a second region.
        let abc = """
        %%score [1 2 3]
        X:1
        L:1/4
        %%score [1 2]
        V:1
        V:2
        V:3
        K:C
        V:1
        CDEF|
        V:2
        GABc|
        V:3
        cdef|
        """
        let parsed = tune(abc)
        #expect(parsed.staffPlans.filter { $0.effectiveFromStave == 0 }.count == 2)

        let regions = PlanRegions.segment(parsed)
        #expect(regions.count == 1)
        // The later plan won: two staves print, not three.
        #expect(stavesPerSystem(abc) == [2])
    }

    @Test("A body plan opens a second region at the stave it governs from")
    func bodyPlanOpensARegion() {
        let regions = PlanRegions.segment(
            tune(threeVoices(header: "%%score [1 2 3]", body: "%%score [1 2]")))
        #expect(regions.map(\.staves) == [0..<1, 1..<2])
        #expect(regions.allSatisfy { $0.plan != nil })
    }

    @Test("A body plan with no plan before it leaves the opening region unplanned")
    func openingRegionCanHaveNoPlan() {
        let regions = PlanRegions.segment(tune(threeVoices(header: "", body: "%%score [1 2]")))
        #expect(regions.map(\.staves) == [0..<1, 1..<2])
        #expect(regions[0].plan == nil)
        #expect(regions[1].plan != nil)
    }

    @Test("A plan that starts past the end of the music governs nothing")
    func planPastTheEndIsDropped() {
        // The trailing `%%score` is the last thing in the body, so it governs stave 2 — a
        // stave the tune never writes.  Cutting a region there would produce an empty one.
        let abc = threeVoices(header: "%%score [1 2 3]") + "\n%%score [1]"
        let parsed = tune(abc)
        #expect(parsed.staffPlans.map(\.effectiveFromStave) == [0, 2])
        #expect(PlanRegions.segment(parsed).map(\.staves) == [0..<2])
    }

    // MARK: - The page

    @Test("%%score [1 2 3] then %%score [1 2] renders three staves, then two")
    func staffCountChangesMidTune() {
        #expect(stavesPerSystem(
            threeVoices(header: "%%score [1 2 3]", body: "%%score [1 2]")) == [3, 2])
    }

    @Test("The system at a region boundary is broken there, not stretched across it")
    func theBoundaryIsASystemBreak() {
        // Two staves of one bar each would otherwise pack onto one system: the first line's
        // bar is nowhere near a page wide.  The plan change forces the break.
        let abc = threeVoices(header: "%%score [1 2 3]", body: "%%score [1 2]")
        let systems = render(abc).pages.flatMap(\.systems)
        #expect(systems.count == 5)
        // Every staff of the first group came from the first line-set, and none of the
        // second group's did.
        #expect(systems.prefix(3).allSatisfy { $0.abcLine == systems[0].abcLine })
        #expect(systems.suffix(2).allSatisfy { $0.abcLine != systems[0].abcLine })
    }

    @Test("Anchor lines stay monotonic across a region boundary")
    func anchorsStayMonotonic() {
        let lines = anchorLines(threeVoices(header: "%%score [1 2 3]", body: "%%score [1 2]"))
        #expect(lines == lines.sorted())
        #expect(lines.first != lines.last)
    }

    @Test("A voice a later plan names again resumes on its own staff")
    func aDroppedVoiceComesBack() {
        let abc = ([
            "X:1", "L:1/4", "%%score [1 2]",
            "V:1", "V:2", "K:C",
            "V:1", "CDEF|", "V:2", "GABc|",
            "%%score [1]",
            "V:1", "CDEF|", "V:2", "GABc|",
            "%%score [1 2]",
            "V:1", "cdef|", "V:2", "GABc|"
        ] as [String]).joined(separator: "\n")

        #expect(stavesPerSystem(abc) == [2, 1, 2])
        // The middle region does not print voice 2, and §11.1 says so out loud.
        let dropped = render(abc).diagnostics.filter { $0.code == .voiceNotInStaffPlan }
        #expect(dropped.count == 1)
        #expect(dropped.first?.message.contains("'2'") == true)
    }

    @Test("A voice the source leaves out of a region resumes on its own line after it")
    func aVoiceOmittedFromARegionKeepsItsLine() {
        // Issue #102: the same tune as `aDroppedVoiceComesBack`, written the way an author
        // actually writes it — voice 2 has no line in the middle line-set, because the plan
        // there does not print it.  Its last line must be drawn in the last region, not
        // attributed to the middle one and dropped.
        let abc = ([
            "X:1", "L:1/4", "%%score [1 2]",
            "V:1", "V:2", "K:C",
            "V:1", "CDEF|", "V:2", "GABc|",
            "%%score [1]",
            "V:1", "CDEF|",
            "%%score [1 2]",
            "V:1", "cdef|", "V:2", "GABc|"
        ] as [String]).joined(separator: "\n")

        #expect(stavesPerSystem(abc) == [2, 1, 2])
        // Nothing to say about it: an empty stave under a plan that prints no staff for the
        // voice is exactly what the source asked for.
        #expect(render(abc).diagnostics.isEmpty)
    }

    @Test("Only the tune's very last system is the last one, however many regions there are")
    func onlyTheFinalRegionEndsTheTune() {
        // `justifyLastSystem` is off by default, so only a system marked last is left short;
        // a region boundary in the middle must not leave the system before it unstretched.
        let abc = threeVoices(header: "%%score [1 2 3]", body: "%%score [1 2]")
        let systems = render(abc).pages.flatMap(\.systems)
        let firstRegionWidth = systems[0].width
        let lastRegionWidth  = systems[3].width
        #expect(firstRegionWidth > lastRegionWidth)
        #expect(systems.prefix(3).allSatisfy { $0.width == firstRegionWidth })
    }

    @Test("A time signature is drawn on the tune's first system only, not on each region's")
    func theMeterDoesNotRepeatAtARegionBoundary() {
        // The header eats width, so the first system's music starts further right than the
        // second region's, which opens with clef and key alone.
        let abc = ([
            "X:1", "L:1/4", "M:4/4", "%%score [1 2]",
            "V:1", "V:2", "K:C",
            "V:1", "CDEF|", "V:2", "GABc|",
            "%%score [1]",
            "V:1", "CDEF|", "V:2", "GABc|"
        ] as [String]).joined(separator: "\n")
        let systems = render(abc).pages.flatMap(\.systems)
        #expect(systems.count == 3)
        // Bar lines are the only thing that moves: same page, same music, narrower header.
        let firstBarOfSystem = systems.map { $0.barlineXs.first ?? 0 }
        #expect(firstBarOfSystem[2] < firstBarOfSystem[0])
    }
}
