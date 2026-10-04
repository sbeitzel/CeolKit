import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #197: a repeat sign that falls on a system break is split across it.  The system
/// that ends there closes with the half that looks back — a plain bar line for `|:` and
/// `[|:`, an end-repeat for `::` — and the next system opens with the start-repeat.  Drawn
/// whole at the end of a system, the sign's dots and thick line landed past the staff.
///
/// End to end — source in, SVG out — because what is wrong is where strokes land on the page.
@Suite("Repeat Signs at a System Break")
struct RepeatAtSystemBreakTests {

    private let engravingDefaults = try! BravuraMetadata.load().engravingDefaults

    /// One vertical stroke of the emitted drawing.
    private struct Stroke {
        let x: Double, y1: Double, y2: Double, width: Double
    }

    /// A repeat dot, read from the non-painting `<text>` copy `.both` leaves in the document.
    private struct Dot {
        let x: Double, y: Double
    }

    private func render(_ body: String) -> (svg: String, staves: [SystemGeometry]) {
        let abc = ["X:1", "T:Repeats", "M:6/8", "L:1/8", "K:G", body].joined(separator: "\n")
        var config = SVGRenderConfig()
        config.textRendering = .both
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config).render(score, diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    /// The bar-line strokes across `staff`: vertical, spanning the staff from its top line,
    /// and heavier than a staff line (a stem is lighter).
    private func barStrokes(in svg: String, on staff: SystemGeometry) -> [Stroke] {
        let tolerance = staff.staffLineGap * 0.1
        let staffLineWidth = engravingDefaults.staffLineThickness * staff.staffLineGap
        return svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"(?: stroke="[^"]*")? stroke-width="([-0-9.]+)"/)
            .compactMap { match -> Stroke? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      let width = Double(match.5), abs(x1 - x2) < 1e-9 else { return nil }
                return Stroke(x: x1, y1: min(y1, y2), y2: max(y1, y2), width: width)
            }
            .filter { abs($0.y1 - staff.topY) < tolerance && $0.width > staffLineWidth }
            .sorted { $0.x < $1.x }
    }

    /// The repeat dots drawn inside `staff`.
    private func dots(in svg: String, on staff: SystemGeometry) -> [Dot] {
        let dot = String(SMuFLGlyph.repeatDot.character)
        return svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>([^<]*)<\/text>/)
            .compactMap { match -> Dot? in
                guard String(match.3) == dot,
                      let x = Double(match.1), let y = Double(match.2) else { return nil }
                return Dot(x: x, y: y)
            }
            .filter { $0.y > staff.topY && $0.y < staff.bottomY }
    }

    private var thickWidth: Double { engravingDefaults.thickBarlineThickness }

    private func isThick(_ stroke: Stroke, on staff: SystemGeometry) -> Bool {
        abs(stroke.width - thickWidth * staff.staffLineGap) < 1e-6
    }

    /// Nothing of line 1's closing bar is drawn past the end of its staff.
    private func expectNothingPastStaffEnd(_ svg: String, _ staff: SystemGeometry) {
        let tolerance = staff.staffLineGap * 0.1
        for stroke in barStrokes(in: svg, on: staff) {
            #expect(stroke.x <= staff.right + tolerance)
        }
        for dot in dots(in: svg, on: staff) {
            #expect(dot.x < staff.right)
        }
    }

    @Test(arguments: ["|:", "[|:"])
    func startRepeatAtLineEndClosesWithASingleBar(sign: String) {
        let (svg, staves) = render("GAB cde | dcB A3 \(sign)\nB2c d2d | cdc B3 :|")
        try! #require(staves.count == 2)
        let (line1, line2) = (staves[0], staves[1])

        expectNothingPastStaffEnd(svg, line1)
        #expect(dots(in: svg, on: line1).isEmpty)
        // Line 1 closes with one thin stroke at the end of its staff.
        let closing = barStrokes(in: svg, on: line1).filter { $0.x > line1.right - line1.staffLineGap }
        #expect(closing.count == 1)
        if let last = closing.last { #expect(!isThick(last, on: line1)) }

        // Line 2 opens with the start-repeat: its dots sit right of its first bar stroke.
        let strokes2 = barStrokes(in: svg, on: line2)
        let leading = dots(in: svg, on: line2).filter { $0.x < line2.left + line2.width / 2 }
        #expect(leading.count == 2)
        if let firstBar = strokes2.first {
            #expect(leading.allSatisfy { $0.x > firstBar.x })
        }
    }

    @Test func endAndStartRepeatAtLineEndIsSplit() {
        let (svg, staves) = render("GAB cde | dcB A3 ::\nB2c d2d | cdc B3 :|")
        try! #require(staves.count == 2)
        let (line1, line2) = (staves[0], staves[1])

        expectNothingPastStaffEnd(svg, line1)
        // Line 1 closes with the end-repeat: thick stroke at the staff end, dots to its left.
        let dots1 = dots(in: svg, on: line1)
        #expect(dots1.count == 2)
        if let last = barStrokes(in: svg, on: line1).last {
            #expect(isThick(last, on: line1))
            #expect(dots1.allSatisfy { $0.x < last.x })
        }

        // Line 2 opens with the start-repeat only: no dots left of its first bar stroke.
        let strokes2 = barStrokes(in: svg, on: line2)
        let leading = dots(in: svg, on: line2).filter { $0.x < line2.left + line2.width / 2 }
        #expect(leading.count == 2)
        if let firstBar = strokes2.first {
            #expect(leading.allSatisfy { $0.x > firstBar.x })
        }
    }

    @Test(arguments: ["|:", "[|:"])
    func midLineStartRepeatIsThickThinDots(sign: String) {
        let (svg, staves) = render("GAB cde \(sign) dcB A3 :|")
        try! #require(staves.count == 1)
        let staff = staves[0]
        // Issue #208: abcm2ps draws `|:` as it draws `[|:` — thick, thin, dots.
        let middle = barStrokes(in: svg, on: staff).filter {
            $0.x > staff.left + staff.staffLineGap && $0.x < staff.right - 2 * staff.staffLineGap
        }
        try! #require(middle.count == 2)
        #expect(isThick(middle[0], on: staff))
        #expect(!isThick(middle[1], on: staff))
        let around = dots(in: svg, on: staff).filter { abs($0.x - middle[1].x) < 2 * staff.staffLineGap }
        #expect(around.count == 2)
        #expect(around.allSatisfy { $0.x > middle[1].x })
    }

    @Test func midLineStartRepeatDrawsAsSectionRepeatStart() {
        // The same bar complex, the same width: the two signs draw identically.
        let plain   = render("GAB cde |: dcB A3 :|")
        let section = render("GAB cde [|: dcB A3 :|")
        try! #require(plain.staves.count == 1 && section.staves.count == 1)
        let a = barStrokes(in: plain.svg, on: plain.staves[0])
        let b = barStrokes(in: section.svg, on: section.staves[0])
        #expect(a.map(\.x) == b.map(\.x))
        #expect(a.map(\.width) == b.map(\.width))
        #expect(dots(in: plain.svg, on: plain.staves[0]).map(\.x)
                == dots(in: section.svg, on: section.staves[0]).map(\.x))
    }

    @Test func midLineDoubleRepeatIsDotsThickThickDots() {
        let (svg, staves) = render("GAB cde :: dcB A3 :|")
        try! #require(staves.count == 1)
        let staff = staves[0]
        // Issue #208: abcm2ps draws `::` as `:][:` (its `%%dblrepbar` default).
        let thick = barStrokes(in: svg, on: staff).filter { isThick($0, on: staff) && $0.x < staff.right - staff.staffLineGap }
        try! #require(thick.count == 2)
        #expect(barStrokes(in: svg, on: staff).filter { !isThick($0, on: staff) && $0.x < staff.right - staff.staffLineGap }.isEmpty)
        let (first, second) = (thick[0], thick[1])
        // The bars stand `barlineSeparation` apart, edge to edge.
        let gap = (second.x - first.x - thickWidth * staff.staffLineGap) / staff.staffLineGap
        #expect(abs(gap - engravingDefaults.barlineSeparation) < 1e-6)
        let around = dots(in: svg, on: staff).filter { $0.x > first.x - 2 * staff.staffLineGap && $0.x < second.x + 2 * staff.staffLineGap }
        #expect(around.filter { $0.x < first.x }.count == 2)
        #expect(around.filter { $0.x > second.x }.count == 2)
        #expect(around.count == 4)
        // The dots stand clear of the thick bars: `repeatBarlineDotSeparation` from their
        // edges, not from their centres.
        let clearance = (thickWidth / 2 + engravingDefaults.repeatBarlineDotSeparation) * staff.staffLineGap
        for dot in around where dot.x > second.x {
            #expect(abs(dot.x - second.x - clearance) < 1e-6)
        }
    }

    /// The `::` drawn right of `x`, checked as `:][:` — two dots, thick, thick, two dots —
    /// and nothing of it left of `x`.  Its bars are the first two thick strokes past `x`.
    private func expectWholeDoubleRepeat(_ svg: String, on staff: SystemGeometry,
                                         after x: Double) {
        let thick = Array(barStrokes(in: svg, on: staff).filter {
            isThick($0, on: staff) && $0.x > x
        }.prefix(2))
        try! #require(thick.count == 2)
        let (first, second) = (thick[0], thick[1])
        let around = dots(in: svg, on: staff).filter {
            $0.x > x && $0.x < second.x + 2 * staff.staffLineGap
        }
        #expect(around.filter { $0.x < first.x }.count == 2)
        #expect(around.filter { $0.x > second.x }.count == 2)
        #expect(around.count == 4)
    }

    @Test func doubleRepeatOpeningALineAfterItsOwnBarIsDrawnWhole() {
        // Issue #212: `:|` closes line 1 and a separate `::` opens line 2.  Nothing was split
        // across the break, so the `::` is drawn as written: `:][:`, as abcm2ps draws it.
        let (svg, staves) = render("GAB cde |: dcB A3 :|\n:: dcB A3 |: GAB cde :|]")
        try! #require(staves.count == 2)
        let (line1, line2) = (staves[0], staves[1])

        expectNothingPastStaffEnd(svg, line1)
        // Its leading dots stand no further left than a `|:` opening the line would.
        let plain = render("GAB cde |: dcB A3 :|\n|: dcB A3 |: GAB cde :|]")
        try! #require(plain.staves.count == 2)
        let startRepeat = try! #require(barStrokes(in: plain.svg, on: plain.staves[1]).first)
        expectWholeDoubleRepeat(svg, on: line2, after: startRepeat.x - line2.staffLineGap / 2)
        // Its leftmost ink starts where the `|:`'s thick line does, as abcm2ps sets them.
        let thickEdge = startRepeat.x - startRepeat.width / 2
        #expect(abs(leadingInk(svg, on: line2) - thickEdge) < 1e-3)
    }

    /// The leftmost ink — bar stroke edge or repeat dot — in the first half of `staff`.
    private func leadingInk(_ svg: String, on staff: SystemGeometry) -> Double {
        let half = staff.left + staff.width / 2
        let strokes = barStrokes(in: svg, on: staff).filter { $0.x < half }.map { $0.x - $0.width / 2 }
        let dotXs = dots(in: svg, on: staff).filter { $0.x < half }.map(\.x)
        return (strokes + dotXs).min() ?? .infinity
    }

    /// Issue #212: every bar is drawn as written.  A bar that opens a line after a bar of its
    /// own is a second bar, not the first restated, and abcm2ps draws it — its leftmost ink
    /// where a `|:`'s thick line would start.
    @Test(arguments: [("|", 1), ("||", 2), (":|", 2), ("|]", 2), ("::", 2)])
    func barOpeningALineAfterItsOwnBarIsDrawn(sign: String, strokes: Int) {
        let (svg, staves) = render("GAB cde |\n\(sign) dcB A3 |")
        try! #require(staves.count == 2)
        let line2 = staves[1]
        let opening = barStrokes(in: svg, on: line2).filter { $0.x < line2.left + line2.width / 2 }
        #expect(opening.count == strokes)

        let plain = render("GAB cde |\n|: dcB A3 |")
        try! #require(plain.staves.count == 2)
        let startRepeat = try! #require(barStrokes(in: plain.svg, on: plain.staves[1]).first)
        #expect(leadingInk(svg, on: line2) >= startRepeat.x - startRepeat.width / 2 - 1e-3)
    }

    /// A bar that ends a line is not restated at the head of the next (issue #197), and
    /// abcm2ps does not restate these either.
    @Test(arguments: ["|", "||", "|]", ":|"])
    func barEndingALineIsNotRestated(sign: String) {
        let (svg, staves) = render("GAB cde \(sign)\ndcB A3 |")
        try! #require(staves.count == 2)
        let line2 = staves[1]
        #expect(barStrokes(in: svg, on: line2).filter { $0.x < line2.left + line2.width / 2 }.isEmpty)
        #expect(dots(in: svg, on: line2).filter { $0.x < line2.left + line2.width / 2 }.isEmpty)
    }

    /// Issue #212: two bars written back to back part way through a line are both drawn,
    /// apart — never one on top of the other.
    @Test(arguments: [("| |", 2), ("|] [|", 4), ("|| ||", 4), (":| :|", 4), (":| |:", 4)])
    func backToBackBarsMidLineAreBothDrawnApart(pair: String, strokes: Int) {
        let (svg, staves) = render("GAB cde \(pair) dcB A3 |]")
        try! #require(staves.count == 1)
        let staff = staves[0]
        let middle = barStrokes(in: svg, on: staff).filter {
            $0.x > staff.left + staff.staffLineGap && $0.x < staff.right - 2 * staff.staffLineGap
        }
        try! #require(middle.count == strokes)
        // The two bars' strokes are each a bar's own width apart; between the bars there is
        // a gap of the kind abcm2ps leaves.
        let gaps = zip(middle, middle.dropFirst()).map { $1.x - $0.x }
        let widest = try! #require(gaps.max())
        #expect(widest > 2 * staff.staffLineGap)
        #expect(gaps.allSatisfy { $0 > 0 })
    }

    @Test func doubleRepeatAfterAnEndRepeatMidLineIsDrawnWhole() {
        // `:| ::` mid-line is two bars, and both are drawn — the `::` clear of the `:|`.
        let (svg, staves) = render("GAB cde :| :: dcB A3 :|")
        try! #require(staves.count == 1)
        let staff = staves[0]
        let strokes = barStrokes(in: svg, on: staff).filter {
            $0.x > staff.left + staff.staffLineGap && $0.x < staff.right - 2 * staff.staffLineGap
        }
        // `:|` is thin, thick; then the `::`'s two thick bars.
        try! #require(strokes.count == 4)
        #expect(!isThick(strokes[0], on: staff))
        #expect(strokes[1...].allSatisfy { isThick($0, on: staff) })
        let endRepeatEdge = strokes[1].x + thickWidth * staff.staffLineGap / 2
        expectWholeDoubleRepeat(svg, on: staff, after: endRepeatEdge)
    }
}
