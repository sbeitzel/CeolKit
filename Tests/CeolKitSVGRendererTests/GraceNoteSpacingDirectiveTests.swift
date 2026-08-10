//
//  GraceNoteSpacingDirectiveTests.swift
//  CeolKitSVGRendererTests
//
//  Rendering behaviour of %%ceolkit:gracenotespacing (issue #42).
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("%%ceolkit:gracenotespacing rendering")
struct GraceNoteSpacingDirectiveTests {

    /// One three-note grace group, and quarter notes throughout so no ordinary beam is
    /// drawn: the only horizontal lines in the document are the staff lines and the grace
    /// group's own beams.
    private static let tuneBody = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        {gcd}A A A A|
        """

    private func render(_ abc: String) throws -> [String] {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().render(score)
    }

    private struct HorizontalLine {
        let x1: Double
        let x2: Double
        let y: Double
        var length: Double { x2 - x1 }
    }

    /// Every horizontal `<line>` element in `svg`, in document order.
    private func horizontalLines(in svg: String) -> [HorizontalLine] {
        svg.matches(of: /<line x1="([\d.-]+)" y1="([\d.-]+)" x2="([\d.-]+)" y2="([\d.-]+)"/)
            .compactMap { match -> HorizontalLine? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      y1 == y2 else { return nil }
                return HorizontalLine(x1: x1, x2: x2, y: y1)
            }
    }

    /// The y of each system's top staff line, and the indices into `horizontalLines(in:)`
    /// of every line that is a staff line.
    ///
    /// `emitStaffLines` opens each system with exactly five consecutive lines sharing one
    /// x range, which tells a staff apart from every other horizontal line on the page.
    /// Length alone does not: two tunes with different spacings have different natural
    /// widths, so the narrower tune's staff is shorter than the wider tune's.
    private func staves(in svg: String) -> (tops: [Double], staffLines: Set<Int>) {
        let lines = horizontalLines(in: svg)
        var tops: [Double] = []
        var staffLines: Set<Int> = []
        var i = 0
        while i + 4 < lines.count {
            let staff = lines[i ..< i + 5]
            if staff.allSatisfy({ $0.x1 == lines[i].x1 && $0.x2 == lines[i].x2 }) {
                tops.append(lines[i].y)
                staffLines.formUnion(i ..< i + 5)
                i += 5
            } else {
                i += 1
            }
        }
        return (tops, staffLines)
    }

    /// Length of the grace beam on each system of `svg`, in document order.
    ///
    /// A grace beam runs from the first stem of the group to the last, so its length is
    /// `(noteCount - 1) × advance` — the directive's effect on the drawn page, measured
    /// directly.  Grace stems point up, so the beams sit above their own staff and below
    /// the staff before it; the test tunes carry one grace group per system, and are
    /// written in quarter notes so no ordinary beam is drawn to be mistaken for one.
    private func graceBeamLengths(in svg: String) -> [Double] {
        let lines = horizontalLines(in: svg)
        let (tops, staffLines) = staves(in: svg)
        let beams = lines.enumerated().filter { !staffLines.contains($0.offset) }.map(\.element)
        return tops.enumerated().compactMap { index, top in
            let floor = index == 0 ? -Double.infinity : tops[index - 1]
            return beams.first { $0.y < top && $0.y > floor }?.length
        }
    }

    /// Width of the first system's staff lines — its natural width, since the last system
    /// of a tune is not justified by default.
    private func staffWidth(in svg: String) throws -> Double {
        try #require(horizontalLines(in: svg).map(\.length).max())
    }

    /// `pages` with the scroll-sync metadata comment removed: adding a directive line
    /// shifts every following ABC line number, so those anchors legitimately differ
    /// between two sources that must nevertheless engrave identically.
    private func drawingOnly(_ pages: [String]) -> [String] {
        pages.map { $0.replacing(/<!-- ceolkit-meta: [^>]*-->/, with: "") }
    }

    private func directive(_ value: String, on body: String = tuneBody) -> String {
        body.replacing("K:C", with: "%%ceolkit:gracenotespacing \(value)\nK:C")
    }

    @Test("The directive sets the step between grace noteheads")
    func directiveSetsGraceStep() throws {
        let plainPage = try #require(try render(Self.tuneBody).first)
        let widePage  = try #require(try render(directive("2.1")).first)

        let plainBeam = try #require(graceBeamLengths(in: plainPage).first)
        let wideBeam  = try #require(graceBeamLengths(in: widePage).first)

        // The beam spans two steps for a three-note group, so its length is proportional
        // to the spacing factor: 2.1 is exactly twice the 1.05 default.
        #expect(abs(wideBeam - plainBeam * 2.0) < 1e-6)
    }

    @Test("A wider grace step widens the music it has to fit")
    func widerStepWidensTheSystem() throws {
        let plainPage = try #require(try render(Self.tuneBody).first)
        let widePage  = try #require(try render(directive("2.5")).first)
        #expect(try staffWidth(in: widePage) > staffWidth(in: plainPage))
    }

    @Test("The step applies per tune — only the tune carrying it is respaced")
    func spacingIsScopedToItsTune() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        {gcd}A A A A|

        X:2
        T:Second
        M:4/4
        L:1/4
        %%ceolkit:gracenotespacing 2.1
        K:C
        {gcd}A A A A|
        """
        let page = try #require(try render(abc).first)
        let beams = graceBeamLengths(in: page)
        try #require(beams.count == 2)
        #expect(abs(beams[1] - beams[0] * 2.0) < 1e-6)
    }

    @Test("A preamble step governs every following tune")
    func preambleStepPersistsAcrossTunes() throws {
        let abc = """
        %%ceolkit:gracenotespacing 2.1
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        {gcd}A A A A|

        X:2
        T:Second
        M:4/4
        L:1/4
        K:C
        {gcd}A A A A|
        """
        let page = try #require(try render(abc).first)
        let beams = graceBeamLengths(in: page)
        try #require(beams.count == 2)
        #expect(abs(beams[0] - beams[1]) < 1e-9)

        let plainPage = try #require(try render(Self.tuneBody).first)
        let plainBeam = try #require(graceBeamLengths(in: plainPage).first)
        #expect(abs(beams[0] - plainBeam * 2.0) < 1e-6)
    }

    @Test("The renderer default engraves identically to no directive at all")
    func defaultStepMatchesAbsentDirective() throws {
        let plain   = try render(Self.tuneBody)
        let spelled = try render(directive(String(SVGRenderConfig().graceNoteSpacing)))
        #expect(drawingOnly(plain) == drawingOnly(spelled))
    }

    @Test("A step below 1 would overlap noteheads — the tune stays at the renderer default")
    func invalidStepFallsBackToDefault() throws {
        let plain   = try render(Self.tuneBody)
        let invalid = try render(directive("0.5"))
        #expect(drawingOnly(plain) == drawingOnly(invalid))
    }

    @Test("The step is a ratio, so %%ceolkit:scale does not compound it")
    func stepIsIndependentOfScale() throws {
        let unscaled = try #require(try render(directive("2.1")).first)
        let scaled   = try #require(
            try render(directive("2.1").replacing("K:C", with: "%%ceolkit:scale 0.5\nK:C")).first)

        let unscaledBeam = try #require(graceBeamLengths(in: unscaled).first)
        let scaledBeam   = try #require(graceBeamLengths(in: scaled).first)

        // Halving the staff size halves the notehead the step is measured in, and nothing
        // more: a step that were itself scaled would land at a quarter, not a half.
        #expect(abs(scaledBeam - unscaledBeam * 0.5) < 1e-6)
    }
}
