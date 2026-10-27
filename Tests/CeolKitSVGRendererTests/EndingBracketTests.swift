//
//  EndingBracketTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #108: the bracket over a variant ending — `|1`, `|2`, `[1,2`, `|1-3` — which was
//  parsed onto the measure and drawn by nothing.
//

import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// What a variant ending puts on the page (ABC v2.2 §4.19).
///
/// Read out of the emitted SVG rather than off the layout, for the reason the shared-staff
/// and lyric suites give: a bracket the layout believes it placed and one that got drawn
/// are two different claims, and only the second is what a player sees.  Rendered through
/// ``textProbeRenderer`` so the labels arrive as `<text>` with their content intact.
@Suite("Variant endings: the bracket over a repeat")
struct EndingBracketTests {

    private let metadata = try! BravuraMetadata.load()

    private func tune(_ body: String) -> String {
        ["X:1", "T:Endings", "M:4/4", "L:1/4", "K:C", body].joined(separator: "\n") + "\n"
    }

    private func render(_ abc: String) throws -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let pages = try textProbeRenderer().render(score, diagnostics: &diagnostics)
        return (pages.joined(), try SVGGeometry.pages(from: pages).flatMap(\.systems))
    }

    // MARK: - Reading the drawing back

    private struct Stroke {
        let x1: Double, y1: Double, x2: Double, y2: Double, width: Double?
        var isVertical: Bool { abs(x1 - x2) < 1e-9 }
        var isHorizontal: Bool { abs(y1 - y2) < 1e-9 }
    }

    private func strokes(in svg: String) -> [Stroke] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"(?: stroke="[^"]*")?(?: stroke-width="([-0-9.]+)")?/)
            .compactMap { match in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4) else { return nil }
                return Stroke(x1: x1, y1: y1, x2: x2, y2: y2,
                              width: match.5.flatMap { Double($0) })
            }
    }

    /// One bracket recovered from the drawing: its rule, and the hooks that drop from it.
    private struct DrawnBracket {
        let left: Double, right: Double, y: Double
        let hasStartHook: Bool, hasEndHook: Bool
        let label: String?
    }

    /// The ending brackets drawn above `staff`.
    ///
    /// A bracket's rule is the one horizontal stroke that stands *above* the staff and is
    /// drawn at the ending-bracket weight — the staff lines themselves are thinner, the
    /// ledger lines are shorter than any measure, and the beams are drawn as filled paths
    /// rather than strokes.  Its hooks are the vertical strokes that begin on it.
    private func brackets(in svg: String, above staff: SystemGeometry) -> [DrawnBracket] {
        let all = strokes(in: svg)
        let thickness = EndingBracketBand.thickness(metadata: metadata,
                                                    staffSize: staff.staffLineGap)
        let tolerance = staff.staffLineGap * 0.1
        // Above this staff and below whatever is over it: brackets stand in the band the
        // layout engine reserved at the top of the staff's own `extraAbove`.
        let band = (staff.topY - staff.staffLineGap * 12)...(staff.topY - tolerance)

        return all
            .filter { $0.isHorizontal && band.contains($0.y1) }
            .filter { abs(($0.width ?? 0) - thickness) < 1e-6 }
            .sorted { $0.x1 < $1.x1 }
            .map { rule in
                let hooks = all.filter {
                    $0.isVertical && abs($0.y1 - rule.y1) < 1e-6 && $0.y2 > $0.y1
                }
                return DrawnBracket(
                    left: rule.x1, right: rule.x2, y: rule.y1,
                    hasStartHook: hooks.contains { abs($0.x1 - rule.x1) < thickness },
                    hasEndHook: hooks.contains { abs($0.x1 - rule.x2) < thickness },
                    label: label(in: svg, insideBracketFrom: rule.x1, to: rule.x2, ruleY: rule.y1,
                                 staffSize: staff.staffLineGap))
            }
    }

    /// The text standing inside a bracket's left hook, if any.
    private func label(in svg: String, insideBracketFrom left: Double, to right: Double,
                       ruleY: Double, staffSize: Double) -> String? {
        let baselineY = ruleY + EndingBracketBand.labelBaselineOffset(staffSize: staffSize)
        return svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Libertinus Serif"[^>]*>([^<]*)<\/text>/
        ).compactMap { match -> String? in
            guard let x = Double(match.1), let y = Double(match.2),
                  abs(y - baselineY) < 1e-3, x >= left, x <= right else { return nil }
            return String(match.3)
        }.first
    }

    // MARK: - The bracket reaches the page

    @Test("A first and second ending are each drawn with their own bracket")
    func firstAndSecondEndingsAreDrawn() throws {
        let (svg, staves) = try render(tune("|:CDEF|GABc|CDEF|GABc|1CDEF:|2GABC|]"))
        let drawn = brackets(in: svg, above: try #require(staves.first))

        #expect(drawn.count == 2)
        #expect(drawn.map(\.label) == ["1", "2"])

        // Each covers exactly its own bar: the fifth and the sixth.  `|:` opens the system,
        // so the bar line closing measure *n* is `barlineXs[n]`.
        let staff = try #require(staves.first)
        let bars = staff.barlineXs
        #expect(abs(drawn[0].left - bars[4]) < 0.5)
        // The two meet at the `:|`, whose several strokes `CeolKitSVGGeometry` reports at
        // the x of the leftmost of them — hence a staff space of slack on that one bound.
        #expect(abs(drawn[0].right - bars[5]) < staff.staffLineGap)
        #expect(drawn[1].left == drawn[0].right)
        #expect(abs(drawn[1].right - staff.right) < 0.5)
    }

    @Test("A second ending in a last bar with no closing bar line is still drawn")
    func endingInUnclosedLastBarIsDrawn() throws {
        // #246: the same tune with and without the final `|]` draws the same brackets.
        // Read off every system, not just the first: where the bar falls is not what this
        // is about.  Only the labelled rules are compared, since a second system's band also
        // takes in the first system's ledger line under its `C`.
        for body in ["|:CDEF|1GABc:|2CDEF", "|:CDEF|1GABc:|2CDEF|]"] {
            let (svg, staves) = try render(tune(body))
            let drawn = staves.flatMap { brackets(in: svg, above: $0) }
            #expect(drawn.compactMap(\.label) == ["1", "2"], "\(body)")
        }
    }

    @Test("A tune with no variant endings draws no bracket at all")
    func noEndingsNoBracket() throws {
        let (svg, staves) = try render(tune("|:CDEF|GABc:|"))
        #expect(brackets(in: svg, above: try #require(staves.first)).isEmpty)
    }

    @Test("The band is the whole of what a bracket adds to a staff's height")
    func bracketCostsExactlyItsBand() throws {
        // The band is added to `extraAbove` only where a bracket stands in it, so a tune
        // without one is laid out exactly as it was before brackets were drawn, and one with
        // a bracket is pushed down by the band and by nothing else.  Asserted against the
        // staff's own y rather than a stored page, which the snapshot suites do.
        let (_, plain) = try render(tune("|:CDEF|GABc:|"))
        let (_, ending) = try render(tune("|:CDEF|1GABc:|2CDEF|]"))
        let band = EndingBracketBand.height(staffSize: try #require(plain.first).staffLineGap)
        let shift = try #require(ending.first).topY - #require(plain.first).topY
        #expect(abs(shift - band) < 1e-3, "staff moved by \(shift), band is \(band)")
    }

    // MARK: - Hooks

    @Test("The bracket hooks down at the repeat bar and stays open at the final one")
    func hooksFollowTheClosingBar() throws {
        let (svg, staves) = try render(tune("|:CDEF|1GABc:|2CDEF|]"))
        let drawn = brackets(in: svg, above: try #require(staves.first))

        #expect(drawn.count == 2)
        // `:|` sends the player back, so the first ending is closed off.
        #expect(drawn[0].hasStartHook)
        #expect(drawn[0].hasEndHook)
        // `|]` ends the piece; nothing repeats from it, so the bracket is left open.
        #expect(drawn[1].hasStartHook)
        #expect(!drawn[1].hasEndHook)
    }

    // MARK: - Labels

    @Test("|1,2 labels the bracket with the whole list", arguments: [
        ("|:CDEF|1,2GABc:|CDEF|]", "1,2"),
        ("|:CDEF|1-3GABc:|CDEF|]", "1,2,3"),
        ("|:CDEF|[1,2GABc:|CDEF|]", "1,2"),
    ])
    func labelsCarryTheWholeList(body: String, expected: String) throws {
        let (svg, staves) = try render(tune(body))
        let drawn = brackets(in: svg, above: try #require(staves.first))
        #expect(drawn.first?.label == expected)
    }

    // MARK: - Runs of more than one measure

    /// The parser tags only the measure an ending *opens* at — `pendingEndingNumber` is
    /// cleared as soon as a bar closes — so a bracket over a two-bar ending is only right if
    /// the renderer carries it to the bar that closes the ending.
    @Test("The bracket spans every measure of the ending, not just the first")
    func bracketSpansTheWholeEnding() throws {
        let (svg, staves) = try render(tune("|:CDEF|1GABc|CDEF:|2GABC|]"))
        let staff = try #require(staves.first)
        let drawn = brackets(in: svg, above: staff)

        #expect(drawn.count == 2)
        // Bars 2 and 3 together, then bar 4 on its own.
        #expect(abs(drawn[0].left - staff.barlineXs[1]) < 0.5)
        #expect(abs(drawn[0].right - staff.barlineXs[3]) < staff.staffLineGap)
        #expect(drawn[1].left == drawn[0].right)
        #expect(abs(drawn[1].right - staff.right) < 0.5)
    }

    // MARK: - Endings that open part way through a bar

    /// The x of every notehead drawn on the page, left to right.
    private func noteheadXs(in svg: String) -> [Double] {
        let head = String(SMuFLGlyph.noteheadBlack.character)
        return svg.matches(of: /<text x="([-0-9.]+)" y="[-0-9.]+" font-family="Bravura"[^>]*>([^<]*)<\/text>/)
            .filter { String($0.2) == head }
            .compactMap { Double($0.1) }
            .sorted()
    }

    /// The pickup that changes between the first and second time through, as pipe and
    /// fiddle settings write it (#172): the `1` bracket begins over the `e`, not at the bar.
    @Test("A bare [1 in mid-measure starts its bracket at the note after it")
    func midMeasureEndingStartsAtItsNote() throws {
        let abc = ["X:1", "T:mid-bar ending", "M:4/4", "L:1/8", "K:D",
                   "|: d2 fd A2 FA | B2 dB A2 FA | d2 fd a2 f[1 e :| [2 d |]"]
            .joined(separator: "\n") + "\n"
        let (svg, staves) = try render(abc)
        let staff = try #require(staves.first)
        // The `a` stands on a ledger line, stroked at the bracket's weight; the brackets
        // are the rules at the very top of the band.
        let rules = brackets(in: svg, above: staff)
        let drawn = rules.filter { $0.y == rules.map(\.y).min() }
        #expect(drawn.count == 2)
        guard drawn.count == 2 else { return }

        // Noteheads: six in each of the first two bars, then `d f d a f e`, then `d`.
        let heads = noteheadXs(in: svg)
        #expect(heads.count == 19)
        guard heads.count == 19 else { return }
        let f = heads[16], e = heads[17]

        // The bracket starts between the `f` before the ending and the `e` it opens on —
        // well inside the third bar, not at its bar line.
        #expect(drawn[0].label == "1")
        #expect(drawn[0].hasStartHook)
        #expect(drawn[0].left > f)
        #expect(drawn[0].left < e)
        #expect(drawn[0].left > staff.barlineXs[2] + staff.staffLineGap)
        // It still closes at the `:|`, and the second ending still starts there.
        #expect(drawn[0].hasEndHook)
        #expect(drawn[1].label == "2")
        #expect(drawn[1].left == drawn[0].right)
    }

    @Test("An ending written against a bar line still starts at that bar line")
    func barLineEndingStillStartsAtTheBar() throws {
        for body in ["|:CDEF|1GABc:|2CDEF|]", "|:CDEF|[1GABc:|[2CDEF|]"] {
            let (svg, staves) = try render(tune(body))
            let staff = try #require(staves.first)
            let drawn = brackets(in: svg, above: staff)
            #expect(drawn.count == 2)
            #expect(abs((drawn.first?.left ?? 0) - staff.barlineXs[1]) < 0.5, "\(body)")
        }
    }

    @Test("The start of a mid-measure ending reaches its run")
    func runCarriesTheEndingStart() {
        let bars = measures("|:CDEF|GA[1Bc:|[2CDEF|]")
        let (runs, _) = EndingBracketBand.runs(in: bars, continuing: nil)
        #expect(runs.count == 2)
        #expect(runs.first?.startEvent == 2)
        #expect(runs.last?.startEvent == nil)
    }

    /// A bar whose variants differ only in its second half, as pipe settings write it: the
    /// `1` bracket stops where the `2` starts, part way through the same bar.
    @Test("Two endings in one bar each get a bracket, meeting where the second starts")
    func twoEndingsInOneBar() throws {
        let (svg, staves) = try render(tune("|{gcd}c2{g}B<{d}A [1 {g}B2{g}c<e [2 {g}B>e{g}A>B |"))
        let staff = try #require(staves.first)
        let drawn = brackets(in: svg, above: staff)
        #expect(drawn.map(\.label) == ["1", "2"])
        guard drawn.count == 2 else { return }
        // Whether the `1` turns down at its right end cannot be read off the page: the `2`'s
        // start hook stands at that very x.  `runEndsAtTheNextEndingInTheBar` checks the run.
        #expect(drawn[0].hasStartHook)
        #expect(drawn[1].hasStartHook)
        #expect(drawn[1].left == drawn[0].right)
        // Both stand inside the one bar: neither starts at its opening bar line.
        #expect(drawn[0].left > staff.barlineXs[0] + staff.staffLineGap)
        #expect(drawn[1].right <= staff.right + 0.5)
    }

    @Test("A second ending in the same bar ends the first one there")
    func runEndsAtTheNextEndingInTheBar() {
        let bars = measures("|CD [1 EF [2 GA|]")
        let (runs, trailing) = EndingBracketBand.runs(in: bars, continuing: nil)
        #expect(runs.count == 2)
        guard runs.count == 2 else { return }
        #expect(runs[0].label == "1")
        #expect(runs[0].firstMeasure == 0 && runs[0].lastMeasure == 0)
        #expect(runs[0].startEvent != nil)
        #expect(runs[0].endEvent == bars[0].endings[1].startIndex)
        #expect(!runs[0].hasEndHook)
        #expect(runs[1].label == "2")
        #expect(runs[1].startEvent == bars[0].endings[1].startIndex)
        #expect(runs[1].endEvent == nil)
        #expect(trailing == nil)
    }

    // MARK: - %%ceolkit:closevariants (issue #237)

    /// Whether each bracket drawn on each staff turns down at its right end, staff by staff.
    ///
    /// Only what stands below the staff before it counts: the band ``brackets(in:above:)``
    /// searches reaches far enough up to take in the ledger lines under that staff, which
    /// are stroked at the bracket's weight.
    private func endHooks(_ abc: String) throws -> [[Bool]] {
        let (svg, staves) = try render(abc)
        return staves.indices.map { i in
            let floor = i > 0 ? staves[i - 1].bottomY + staves[i].staffLineGap * 2 : -.infinity
            return brackets(in: svg, above: staves[i]).filter { $0.y > floor }.map(\.hasEndHook)
        }
    }

    private let threeEndings = "|:CDEF|1GABc:|2CDEF:|3GABc|]"

    @Test("By default only the endings that close at a repeat bar are hooked")
    func closeVariantsOffByDefault() throws {
        #expect(try endHooks(tune(threeEndings)) == [[true, true, false]])
    }

    @Test("%%ceolkit:closevariants true hooks every ending at its end")
    func closeVariantsHooksEveryEnding() throws {
        #expect(try endHooks(tune("%%ceolkit:closevariants true\n" + threeEndings))
                == [[true, true, true]])
        #expect(try endHooks(tune("%%ceolkit:closevariants true\n|:CDEF|1GABc:|2CDEF|]"))
                == [[true, true]])
    }

    /// Two tunes, the preamble and each header given their own lines.
    private func twoTunes(preamble: String = "", first: String = "",
                          second: String = "") -> String {
        func tune(_ x: Int, _ header: String) -> String {
            "X:\(x)\nT:Endings \(x)\nM:4/4\nL:1/4\n\(header)K:C\n\(threeEndings)\n"
        }
        return preamble + "\n" + tune(1, first) + "\n" + tune(2, second)
    }

    @Test("%%ceolkit:closevariants in the file preamble reaches every tune")
    func closeVariantsInPreambleReachesEveryTune() throws {
        let hooks = try endHooks(twoTunes(preamble: "%%ceolkit:closevariants true\n"))
        #expect(hooks == [[true, true, true], [true, true, true]])
    }

    @Test("%%ceolkit:closevariants in a tune header applies to that tune only")
    func closeVariantsInTuneHeaderIsScopedToTheTune() throws {
        let hooks = try endHooks(twoTunes(first: "%%ceolkit:closevariants true\n"))
        #expect(hooks == [[true, true, true], [true, true, false]])
    }

    @Test("%%ceolkit:closevariants false in a tune header overrides the file setting")
    func closeVariantsTuneOverridesPreamble() throws {
        let hooks = try endHooks(twoTunes(preamble: "%%ceolkit:closevariants true\n",
                                          second: "%%ceolkit:closevariants false\n"))
        #expect(hooks == [[true, true, true], [true, true, false]])
    }

    @Test("Under closevariants an ending is not hooked where it only breaks across systems")
    func closeVariantsLeavesTheSystemBreakOpen() throws {
        let hooks = try endHooks(tune("%%ceolkit:closevariants true\n|:CDEF|1GABc|\nCDEF:|2GABc|]"))
        #expect(hooks == [[false], [true, true]])
    }

    @Test("Under closevariants an ending that stops at a system break is hooked there")
    func closeVariantsHooksAnEndingThatStopsAtTheBreak() throws {
        let hooks = try endHooks(tune("%%ceolkit:closevariants true\n|:CDEF|1GABc|\n|2CDEF|]"))
        #expect(hooks == [[true], [true]])
    }

    @Test("Under closevariants an ending left open at the end of the tune is hooked")
    func closeVariantsHooksTheLastUnclosedEnding() throws {
        #expect(try endHooks(tune("%%ceolkit:closevariants true\n|:CDEF|1GABc:|2CDEF"))
                == [[true, true]])
        #expect(try endHooks(tune("|:CDEF|1GABc:|2CDEF")) == [[true, false]])
    }

    // MARK: - Runs, worked out from the measures

    /// `EndingBracketBand` on its own, where the cases that need a whole page of music to
    /// reach end to end can be stated in a line.
    private func measures(_ body: String) -> [Measure] {
        let score = CeolKitParser().parse(tune(body), options: .default).score
        return score.tunes[0].voices[0].staves[0].measures
    }

    @Test("An ending open at the end of a system is handed to the next one")
    func endingCarriesOverASystemBreak() {
        let bars = measures("|:CDEF|1GABc|CDEF|GABc:|2CDEF|]")
        // Split as the line breaker would: the ending opens in the first half and closes in
        // the second.
        let (first, carried) = EndingBracketBand.runs(in: Array(bars[0..<2]), continuing: nil)
        #expect(first.count == 1)
        #expect(first[0].label == "1")
        #expect(first[0].hasStartHook)
        #expect(!first[0].hasEndHook)   // the ending runs on into the next system
        #expect(carried == [1])

        let (second, trailing) = EndingBracketBand.runs(in: Array(bars[2...]), continuing: carried)
        #expect(second.count == 2)
        // The continuation prints no number and turns down at neither end but the repeat bar:
        // it is the same ending, not a new one.
        #expect(second[0].label == nil)
        #expect(!second[0].hasStartHook)
        #expect(second[0].hasEndHook)
        #expect(second[0].firstMeasure == 0 && second[0].lastMeasure == 1)
        #expect(second[1].label == "2")
        #expect(trailing == nil)
    }

    @Test("A run that meets the next ending ends unhooked at the bar before it")
    func adjacentEndingsDoNotShareABar() {
        let bars = measures("|:CDEF|1GABc|2CDEF|]")
        let (runs, _) = EndingBracketBand.runs(in: bars, continuing: nil)
        #expect(runs.count == 2)
        #expect(runs[0].firstMeasure == 1 && runs[0].lastMeasure == 1)
        #expect(!runs[0].hasEndHook)
        #expect(runs[1].firstMeasure == 2)
    }

    @Test("A tune with no ending numbers produces no runs")
    func noEndingsNoRuns() {
        let (runs, trailing) = EndingBracketBand.runs(in: measures("|:CDEF|GABc:|"),
                                                      continuing: nil)
        #expect(runs.isEmpty)
        #expect(trailing == nil)
    }
}
