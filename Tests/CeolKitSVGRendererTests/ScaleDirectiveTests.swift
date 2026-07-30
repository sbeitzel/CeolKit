//
//  ScaleDirectiveTests.swift
//  CeolKitSVGRendererTests
//
//  Rendering behaviour of %%ceolkit:scale (issue #32).
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("%%ceolkit:scale rendering")
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
        svg.firstMatch(of: /<svg [^>]*(width="[\d.]+" height="[\d.]+")/).map { String($0.1) }
    }

    @Test("%%ceolkit:scale 0.5 halves staff line spacing")
    func halfScaleHalvesStaffSpacing() throws {
        let plainPage  = try #require(try render(Self.tuneBody).first)
        let scaledPage = try #require(
            try render(Self.tuneBody.replacing("K:C", with: "%%ceolkit:scale 0.5\nK:C")).first)

        let plainSpacing  = try #require(staffSpacings(in: plainPage).first)
        let scaledSpacing = try #require(staffSpacings(in: scaledPage).first)

        #expect(plainSpacing == SVGRenderConfig().staffSize)
        #expect(abs(scaledSpacing - plainSpacing * 0.5) < 1e-9)
    }

    @Test("%%ceolkit:scale applies per tune — only the tune carrying it is resized")
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
        %%ceolkit:scale 0.5
        K:C
        CDEF|GABc|
        """
        let page = try #require(try render(abc).first)
        let spacings = staffSpacings(in: page)
        try #require(spacings.count == 2)
        #expect(spacings[0] == SVGRenderConfig().staffSize)
        #expect(abs(spacings[1] - spacings[0] * 0.5) < 1e-9)
    }

    @Test("A preamble %%ceolkit:scale governs every following tune")
    func preambleScalePersistsAcrossTunes() throws {
        let abc = """
        %%ceolkit:scale 0.5
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
        #expect(spacings.allSatisfy { abs($0 - SVGRenderConfig().staffSize * 0.5) < 1e-9 })
    }

    @Test("%%ceolkit:scale 1.0 engraves identically to no directive at all")
    func unitScaleMatchesAbsentDirective() throws {
        let plain = try render(Self.tuneBody)
        let unit  = try render(Self.tuneBody.replacing("K:C", with: "%%ceolkit:scale 1.0\nK:C"))
        #expect(drawingOnly(plain) == drawingOnly(unit))
    }

    @Test("Scaling the music leaves the page size untouched")
    func scaleDoesNotResizePage() throws {
        let plainPage  = try #require(try render(Self.tuneBody).first)
        let scaledPage = try #require(
            try render(Self.tuneBody.replacing("K:C", with: "%%ceolkit:scale 0.5\nK:C")).first)
        let plainAttrs = try #require(pageAttributes(of: plainPage))
        #expect(pageAttributes(of: scaledPage) == plainAttrs)
    }

    @Test("An invalid %%ceolkit:scale leaves the tune at the renderer default")
    func invalidScaleFallsBackToDefault() throws {
        let plain   = try render(Self.tuneBody)
        let invalid = try render(Self.tuneBody.replacing("K:C", with: "%%ceolkit:scale 0\nK:C"))
        #expect(drawingOnly(plain) == drawingOnly(invalid))
    }
}
