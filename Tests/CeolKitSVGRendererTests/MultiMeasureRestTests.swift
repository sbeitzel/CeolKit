//
//  MultiMeasureRestTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #291: a multi-measure rest (`Zn`, n > 1; ABC v2.2 §4.5) is drawn as abcm2ps 8.14
//  draws it — a thick bar on the middle line between two short strokes, with the count over
//  the staff — and is spaced the same whatever `L:` is.
//

import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

@Suite("Multi-measure rests")
struct MultiMeasureRestRenderTests {

    private struct Count {
        let text: String
        let x: Double
        let y: Double
    }

    private struct Rendered {
        let svg: String
        /// The bold numbers drawn: in this renderer, only a multi-measure rest's count.
        let counts: [Count]
        let staff: SystemGeometry
    }

    private func render(_ body: String, unit: String = "1/8") throws -> Rendered {
        let abc = "X:1\nT:Rests\nM:4/4\nL:\(unit)\nK:C\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let pages = try textProbeRenderer().render(score, diagnostics: &diagnostics)
        let svg = pages.joined()
        let counts = svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)"[^>]*font-weight="bold"[^>]*>([0-9]+)<\/text>/
        ).compactMap { match -> Count? in
            guard let x = Double(match.1), let y = Double(match.2) else { return nil }
            return Count(text: String(match.3), x: x, y: y)
        }
        let staff = try #require(SVGGeometry.pages(from: pages).first?.systems.first)
        return Rendered(svg: svg, counts: counts, staff: staff)
    }

    private func drawsWholeRest(_ svg: String) -> Bool {
        svg.contains(SMuFLGlyph.restWhole.character)
    }

    /// The width of every measure after the first, from the bar lines the geometry reader
    /// finds (it reports none at the head of the staff).
    private func measureWidths(_ staff: SystemGeometry) -> [Double] {
        zip(staff.barlineXs, staff.barlineXs.dropFirst()).map { $1 - $0 }
    }

    @Test("Zn draws its count over the staff, and no whole-bar rest")
    func count() throws {
        let rendered = try render("Z6|CDEF GABc|]")
        #expect(rendered.counts.map(\.text) == ["6"])
        #expect(!drawsWholeRest(rendered.svg))
        let count = try #require(rendered.counts.first)
        // Over the top line, in the first measure.
        #expect(count.y < rendered.staff.topY)
        let firstBar = try #require(rendered.staff.barlineXs.first)
        #expect(count.x > rendered.staff.left && count.x < firstBar)
    }

    @Test("The bar is a filled path on the middle line, centred under its count")
    func bar() throws {
        let rendered = try render("Z6|CDEF GABc|]")
        let count = try #require(rendered.counts.first)
        let staff = rendered.staff
        let u = staff.staffLineGap / TextStyles.nominalStaffSize
        let middle = staff.topY + 2 * staff.staffLineGap
        // The bar's top edge: the path's first rectangle.
        let half = MultiMeasureRest.barThickness * u / 2
        let bars = rendered.svg.matches(of: /<path d="M([-0-9.]+) ([-0-9.]+)h([-0-9.]+)v[-0-9.]+h[^"]*Z/)
            .compactMap { match -> (x: Double, y: Double, width: Double)? in
                guard let x = Double(match.1), let y = Double(match.2),
                      let width = Double(match.3) else { return nil }
                return (x, y, width)
            }
            .filter { abs($0.width - MultiMeasureRest.barLength * u) < 0.01 }
        let bar = try #require(bars.first)
        #expect(bars.count == 1)
        #expect(abs(bar.y - (middle - half)) < 0.01)
        #expect(abs(bar.x + bar.width / 2 - count.x) < 0.01)
    }

    @Test("Z and Z1 are an ordinary whole-bar rest", arguments: ["Z", "Z1"])
    func single(rest: String) throws {
        let rendered = try render("\(rest)|CDEF GABc|]")
        #expect(rendered.counts.isEmpty)
        #expect(drawsWholeRest(rendered.svg))
    }

    @Test("Xn takes its measure and draws nothing")
    func invisible() throws {
        let rendered = try render("C8|X6|C8|]")
        #expect(rendered.counts.isEmpty)
        #expect(!drawsWholeRest(rendered.svg))
        let visible = try render("C8|Z6|C8|]")
        let widths = measureWidths(rendered.staff)
        try #require(widths.count == 2)
        #expect(widths == measureWidths(visible.staff))
    }

    @Test("Zn is spaced the same whatever L: is", arguments: ["1/4", "1/16"])
    func unitIndependent(unit: String) throws {
        let eighths = measureWidths(try render("C|Z6|C|]").staff)
        try #require(eighths.count == 2)
        let other = try #require(measureWidths(try render("C|Z6|C|]", unit: unit).staff).first)
        #expect(abs(other - eighths[0]) < 0.01)
    }

    @Test("Z is spaced as a whole-bar rest, not by its multiplier as a note length",
          arguments: ["1/4", "1/8", "1/16"])
    func singleSpacing(unit: String) throws {
        // Between two bars of the same kind, so that only the rests differ.
        let widths = measureWidths(try render("C8|Z|z8|C8|]").staff)
        try #require(widths.count == 3)
        #expect(abs(widths[0] - widths[1]) < 0.01)
        let other = measureWidths(try render("C|Z|Z|C|]", unit: unit).staff)
        try #require(other.count == 3)
        #expect(abs(other[0] - widths[0]) < 0.01)
        #expect(abs(other[1] - widths[0]) < 0.01)
    }

    @Test("A document with a multi-measure rest embeds the bold face its count is set in")
    func embedsBold() throws {
        #expect(try render("Z6|CDEF GABc|]").svg.contains("font-weight: bold;"))
        #expect(try !render("Z|CDEF GABc|]").svg.contains("font-weight: bold;"))
    }
}
