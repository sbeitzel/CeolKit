//
//  AnnotationRenderingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #171: text annotations (`"^text"`, ABC v2.2 §4.19) and chord symbols (§4.18) were
//  parsed onto `Note.annotations` / `Note.chordSymbol`, given space above the staff, and
//  drawn by nothing.
//

import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// What a note's quoted text puts on the page.
///
/// Read out of the emitted SVG, for the reason ``EndingBracketTests`` gives: text the layout
/// reserved room for and text that got drawn are two different claims.  Rendered through
/// ``textProbeRenderer`` so each run arrives as one `<text>` with its content intact, except
/// where the outline mode itself is the subject.
@Suite("Annotations and chord symbols reach the page")
struct AnnotationRenderingTests {

    private func tune(_ body: String) -> String {
        ["X:1", "T:Annotations", "M:4/4", "L:1/4", "K:C", body].joined(separator: "\n") + "\n"
    }

    private func render(_ abc: String, _ renderer: SVGRenderer = textProbeRenderer())
        throws -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let pages = try renderer.render(score, diagnostics: &diagnostics)
        return (pages.joined(), try SVGGeometry.pages(from: pages).flatMap(\.systems))
    }

    private struct Run {
        let x: Double, y: Double, fontSize: Double
        let anchor: String?
        let content: String
    }

    /// Every Libertinus Serif `<text>` run in `svg`.
    private func runs(in svg: String) -> [Run] {
        svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Libertinus Serif" font-size="([-0-9.]+)"[^>]*?(?: text-anchor="([a-z]+)")?>([^<]*)<\/text>/
        ).compactMap { m in
            guard let x = Double(m.1), let y = Double(m.2), let size = Double(m.3) else { return nil }
            return Run(x: x, y: y, fontSize: size, anchor: m.4.map(String.init), content: String(m.5))
        }
    }

    private func run(_ content: String, in svg: String) throws -> Run {
        let matching = runs(in: svg).filter { $0.content == content }
        #expect(matching.count == 1, "expected one run of \"\(content)\", found \(matching.count)")
        return try #require(matching.first)
    }

    // MARK: - Above and below

    @Test("\"^text\" is drawn above the top staff line")
    func aboveAnnotationIsDrawnAboveTheStaff() throws {
        let (svg, staves) = try render(tune(#""^on a note"C D E F|]"#))
        let staff = try #require(staves.first)
        let text = try run("on a note", in: svg)

        // Its descenders too: nothing of it reaches down into the staff.
        let descent = text.fontSize * LibertinusSerifMetrics.descenderRatio
        #expect(text.y + descent < staff.topY)
        // Over the note it was written against — the first in the bar — not somewhere else.
        let finalBar = try #require(staff.barlineXs.last)
        #expect(text.x > staff.left)
        #expect(text.x < finalBar)
    }

    /// The default mode draws the same run as glyph outlines, one `<use>` per inked glyph,
    /// on the baseline the `<text>` run stood on.
    @Test("In outline mode the annotation is drawn as glyphs on the same baseline")
    func aboveAnnotationIsDrawnAsOutlines() throws {
        let abc = tune(#""^on a note"C D E F|]"#)
        let probe = try run("on a note", in: try render(abc).svg)
        let (outlined, staves) = try render(abc, SVGRenderer(config: SVGRenderConfig()))
        let staff = try #require(staves.first)
        #expect(probe.y < staff.topY)

        let glyphYs = outlined.matches(
            of: /<use href="#libertinusSerif-g[0-9]+"[^>]*transform="translate\(([-0-9.]+) ([-0-9.]+)\)/
        ).compactMap { Double($0.2) }
        let onBaseline = glyphYs.filter { abs($0 - probe.y) < 1e-6 }
        // "on a note" inks seven glyphs; the spaces advance without drawing.
        #expect(onBaseline.count == 7)
    }

    @Test("\"_text\" is drawn below the bottom staff line")
    func belowAnnotationIsDrawnBelowTheStaff() throws {
        let (svg, staves) = try render(tune(#""_under"C D E F|]"#))
        let staff = try #require(staves.first)
        let text = try run("under", in: svg)
        let bottomY = staff.topY + 4 * staff.staffLineGap
        #expect(text.y - text.fontSize * LibertinusSerifMetrics.ascenderRatio > bottomY)
    }

    @Test("Consecutive annotations of one placement stack, the first listed at the top")
    func consecutiveAnnotationsStackFirstAtTop() throws {
        let (svg, staves) = try render(tune(#""^one""^two"C D E F|]"#))
        let staff = try #require(staves.first)
        let one = try run("one", in: svg)
        let two = try run("two", in: svg)
        #expect(one.x == two.x)
        #expect(one.y < two.y)
        // A line apart, so the two do not print over each other.
        #expect(two.y - one.y >= one.fontSize * (LibertinusSerifMetrics.ascenderRatio
                                                 + LibertinusSerifMetrics.descenderRatio))
        #expect(two.y + two.fontSize * LibertinusSerifMetrics.descenderRatio < staff.topY)
    }

    @Test("A chord symbol is drawn above the staff, under the note's annotations")
    func chordSymbolIsDrawnUnderAnnotations() throws {
        let (svg, staves) = try render(tune(#""^Fine""Am7"C D E F|]"#))
        let staff = try #require(staves.first)
        let chord = try run("Am7", in: svg)
        let fine = try run("Fine", in: svg)
        #expect(chord.y < staff.topY)
        #expect(fine.y < chord.y)
        #expect(fine.x == chord.x)
    }

    @Test("Chord symbols across a system stand on one line")
    func chordSymbolsShareALine() throws {
        let (svg, _) = try render(tune(#""^Fine""G"C D "D7"E F|]"#))
        let g = try run("G", in: svg)
        let d7 = try run("D7", in: svg)
        #expect(g.y == d7.y)
    }

    @Test("Room is reserved above the staff for every line a note stacks there")
    func stackedLinesAreGivenRoom() throws {
        let (svg, staves) = try render(tune(#""^a""^b""^c""G"C D E F|]"#))
        let staff = try #require(staves.first)
        let title = try run("Annotations", in: svg)
        let top = try run("a", in: svg)
        // The highest line clears the title block rather than printing into it.
        #expect(top.y - top.fontSize * LibertinusSerifMetrics.ascenderRatio
                > title.y + title.fontSize * LibertinusSerifMetrics.descenderRatio)
        let chord = try run("G", in: svg)
        #expect(chord.y < staff.topY)
    }

    // MARK: - Beside the note

    @Test("\"<text\" and \">text\" flank the notehead, level with it")
    func sideAnnotationsFlankTheNote() throws {
        let (svg, staves) = try render(tune(#"C "<(" ">)" B E F|]"#))
        let staff = try #require(staves.first)
        let open = try run("(", in: svg)
        let close = try run(")", in: svg)
        #expect(open.anchor == "end")
        #expect(open.x < close.x)
        #expect(open.y == close.y)
        // B sits on the middle line; the text is centred on it, so its baseline falls within
        // the staff.
        #expect(open.y > staff.topY)
        #expect(open.y < staff.topY + 4 * staff.staffLineGap)
    }

    @Test("\"@x,y text\" is offset from the note by the staff spaces it states")
    func absoluteAnnotationIsOffsetFromTheNote() throws {
        let (svg, _) = try render(tune(#"C "@0,0 here""@2,3 there"B E F|]"#))
        let here = try run("here", in: svg)
        let there = try run("there", in: svg)
        let s = 6.0  // the default staff size, which `%%ceolkit:scale` leaves alone here
        #expect(abs((there.x - here.x) - 2 * s) < 1e-6)
        #expect(abs((here.y - there.y) - 3 * s) < 1e-6)
    }

    // MARK: - Under an ending bracket

    @Test("\"[2 \\\"^text\\\"\" sets the text inside the bracket, clear of the 2")
    func annotationOnAnEndingStandsInsideTheBracket() throws {
        let (svg, staves) = try render(tune(#"|:CDEF|1GABc:|[2 "^repeat of part 2"cBAG|]"#))
        let staff = try #require(staves.first)
        let s = staff.staffLineGap
        let label = try run("2", in: svg)
        let text = try run("repeat of part 2", in: svg)

        // On the number's line, inside the band the bracket stands in.
        #expect(text.y == label.y)
        let ruleY = label.y - EndingBracketBand.labelBaselineOffset(staffSize: s)
        #expect(text.y - text.fontSize * LibertinusSerifMetrics.capHeightRatio > ruleY)
        #expect(text.y < staff.topY)

        // Right of the number, with a gap between them.
        let labelWidth = AnnotationBand.width(of: "2", font: OutlineFontSet.textFace(),
                                              fontSize: label.fontSize)
        #expect(text.x > label.x + labelWidth)
    }

    @Test("A later annotation in the ending stays in the band below the bracket")
    func laterAnnotationInAnEndingIsNotRaised() throws {
        let (svg, _) = try render(tune(#"|:CDEF|1GABc:|[2 "^first"c "^later"BAG|]"#))
        let label = try run("2", in: svg)
        let first = try run("first", in: svg)
        let later = try run("later", in: svg)
        #expect(first.y == label.y)
        #expect(later.y > label.y)
    }

    // MARK: - Before a grace group

    /// Issue #176: text written ahead of the braces was attached to the grace note, where
    /// nothing draws it.
    @Test("\"^x\"{g}A draws the text above the staff")
    func annotationBeforeGraceGroupIsDrawn() throws {
        let (svg, staves) = try render(tune(#""^x"{g}A "G"{ag}B c d|]"#))
        let staff = try #require(staves.first)
        let x = try run("x", in: svg)
        let g = try run("G", in: svg)
        #expect(x.y + x.fontSize * LibertinusSerifMetrics.descenderRatio < staff.topY)
        #expect(g.y < staff.topY)
    }

    @Test("Nothing changes on a staff that carries no quoted text")
    func unannotatedStaffIsUnchanged() throws {
        let (svg, _) = try render(tune("C D E F|]"))
        #expect(runs(in: svg).map(\.content) == ["Annotations"])
    }
}
