//
//  ScaleDirectiveTests.swift
//  CeolKitSVGRendererTests
//
//  Rendering behaviour of the page scale: %%scale, %%pagescale and the deprecated
//  %%ceolkit:scale (issues #32, #203).
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("%%scale / %%pagescale rendering")
struct ScaleDirectiveTests {

    private static let tuneBody = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|
        """

    private func render(_ abc: String) throws -> [String] {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().render(score)
    }

    private struct HorizontalLine {
        let x1: Double
        let x2: Double
        let y: Double
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

    /// Distance between adjacent staff lines for each system in `svg`, in document order.
    ///
    /// `emitStaffLines` opens each system with exactly five consecutive lines sharing one
    /// x range, which tells a staff apart from the ledger lines drawn later inside its
    /// measures — those are notehead-width and do not come five to a run.
    private func staffSpacings(in svg: String) -> [Double] {
        let lines = horizontalLines(in: svg)
        var spacings: [Double] = []
        var i = 0
        while i + 4 < lines.count {
            let staff = lines[i ..< i + 5]
            if staff.allSatisfy({ $0.x1 == lines[i].x1 && $0.x2 == lines[i].x2 }) {
                spacings.append(lines[i + 1].y - lines[i].y)
                i += 5
            } else {
                i += 1
            }
        }
        return spacings
    }

    /// `pages` with the scroll-sync metadata comment removed.
    ///
    /// Adding a directive line to a source shifts every following ABC line number, so the
    /// `abcLine` anchors legitimately differ between two sources that must nevertheless
    /// engrave identically. Everything outside the comment is drawing geometry.
    private func drawingOnly(_ pages: [String]) -> [String] {
        pages.map { $0.replacing(/<!-- ceolkit-meta: [^>]*-->/, with: "") }
    }

    /// The `width`/`height` attributes of the root `<svg>` element, as written.
    private func pageAttributes(of svg: String) -> String? {
        svg.firstMatch(of: /<svg [^>]*(width="[\d.]+pt" height="[\d.]+pt")/).map { String($0.1) }
    }

    private func scaled(_ directive: String) -> String {
        Self.tuneBody.replacing("K:C", with: "\(directive)\nK:C")
    }

    /// The size of every `<text>` run whose content is `content`, in `fontFace` mode.
    private func textSizes(_ content: String, in abc: String) throws -> [Double] {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try textProbeRenderer().render(score).joined()
            .matches(of: /<text [^>]*font-size="([\d.]+)"[^>]*>([^<]*)<\/text>/)
            .filter { $0.2 == content }
            .compactMap { Double($0.1) }
    }

    // MARK: - The baseline

    @Test("With no directive the staff is drawn at abcm2ps's default %%scale 0.75")
    func defaultIsAbcm2psScale() throws {
        let page = try #require(try render(Self.tuneBody).first)
        #expect(staffSpacings(in: page).first == 4.5)
        #expect(SVGRenderConfig().scaledStaffSize == 4.5)
    }

    @Test("%%scale 0.75, %%pagescale 1 and no directive all engrave alike")
    func scaleAndPageScaleAgree() throws {
        let plain = drawingOnly(try render(Self.tuneBody))
        #expect(drawingOnly(try render(scaled("%%scale 0.75"))) == plain)
        #expect(drawingOnly(try render(scaled("%%pagescale 1"))) == plain)
    }

    @Test("%%ceolkit:scale F engraves as %%pagescale F")
    func ceolKitScaleIsPageScale() throws {
        #expect(drawingOnly(try render(scaled("%%ceolkit:scale 0.6")))
                == drawingOnly(try render(scaled("%%pagescale 0.6"))))
    }

    @Test("The host's default scale is what a document without a directive gets")
    func configScaleIsTheDefault() throws {
        let score = CeolKitParser().parse(Self.tuneBody, options: .default).score
        let page = try #require(try SVGRenderer(config: SVGRenderConfig(scale: 1)).render(score).first)
        #expect(staffSpacings(in: page).first == 6)

        // …and a document's own directive still overrides it.
        let directed = CeolKitParser().parse(scaled("%%scale 0.5"), options: .default).score
        let directedPage = try #require(
            try SVGRenderer(config: SVGRenderConfig(scale: 1)).render(directed).first)
        #expect(staffSpacings(in: directedPage).first == 3)
    }

    // MARK: - Size

    @Test("%%scale 0.375 halves staff line spacing")
    func halfScaleHalvesStaffSpacing() throws {
        let plainPage  = try #require(try render(Self.tuneBody).first)
        let scaledPage = try #require(try render(scaled("%%scale 0.375")).first)

        let plainSpacing  = try #require(staffSpacings(in: plainPage).first)
        let scaledSpacing = try #require(staffSpacings(in: scaledPage).first)
        #expect(abs(scaledSpacing - plainSpacing * 0.5) < 1e-9)
    }

    @Test("The title block and words scale with the page; the footer does not")
    func textScalesButNotTheFooter() throws {
        let body = Self.tuneBody + "\nW:the words\n"
        let footer = "%%footer \"the footer\"\n"
        let plain = footer + body
        let half  = footer + "%%pagescale 0.5\n" + body
        #expect(try textSizes("First", in: plain) == [15])
        #expect(try textSizes("First", in: half) == [7.5])
        #expect(try textSizes("the words", in: plain) == [12])
        #expect(try textSizes("the words", in: half) == [6])
        #expect(try textSizes("the footer", in: plain) == [FooterBand.fontSize])
        #expect(try textSizes("the footer", in: half) == [FooterBand.fontSize])
    }

    // MARK: - Scope

    @Test("%%scale applies per tune — only the tune carrying it is resized")
    func scaleIsScopedToItsTune() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|

        X:2
        T:Second
        M:4/4
        L:1/4
        %%scale 0.375
        K:C
        CDEF|GABc|
        """
        let page = try #require(try render(abc).first)
        let spacings = staffSpacings(in: page)
        try #require(spacings.count == 2)
        #expect(spacings[0] == SVGRenderConfig().scaledStaffSize)
        #expect(abs(spacings[1] - spacings[0] * 0.5) < 1e-9)
    }

    @Test("A preamble %%scale governs every following tune")
    func preambleScalePersistsAcrossTunes() throws {
        let abc = """
        %%scale 0.375
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|

        X:2
        T:Second
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|
        """
        let page = try #require(try render(abc).first)
        let spacings = staffSpacings(in: page)
        try #require(spacings.count == 2)
        #expect(spacings.allSatisfy { abs($0 - 2.25) < 1e-9 })
    }

    @Test("A %%scale in the tune body scales the whole tune, and the last one wins")
    func bodyScaleGovernsTheWholeTune() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|
        %%scale 0.6
        GABc|
        %%pagescale 0.5
        CDEF|
        """
        let page = try #require(try render(abc).first)
        let spacings = staffSpacings(in: page)
        try #require(spacings.count == 3)
        #expect(spacings.allSatisfy { abs($0 - 2.25) < 1e-9 })
    }

    @Test("Scaling the music leaves the page size untouched")
    func scaleDoesNotResizePage() throws {
        let plainPage  = try #require(try render(Self.tuneBody).first)
        let scaledPage = try #require(try render(scaled("%%scale 0.375")).first)
        let plainAttrs = try #require(pageAttributes(of: plainPage))
        #expect(pageAttributes(of: scaledPage) == plainAttrs)
    }

    @Test("An invalid %%scale leaves the tune at the default")
    func invalidScaleFallsBackToDefault() throws {
        let plain = try render(Self.tuneBody)
        #expect(drawingOnly(plain) == drawingOnly(try render(scaled("%%scale 0"))))
        #expect(drawingOnly(plain) == drawingOnly(try render(scaled("%%pagescale nope"))))
    }
}
