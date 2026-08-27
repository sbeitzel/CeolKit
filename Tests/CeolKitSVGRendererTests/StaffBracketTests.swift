import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #70: a `%%score` / `%%staves` span is drawn as a bracket at the left edge, and the
/// space it stands in is reserved before the music is broken into lines (ABC v2.2 §11.1).
///
/// End to end — source in, SVG out — because the two halves only mean anything together:
/// the reservation is right when the bracket lands inside the page margin and the music
/// still reaches the right one.
@Suite("Staff Brackets")
struct StaffBracketTests {

    private let config = SVGRenderConfig()
    private let metadata = try! BravuraMetadata.load()

    /// One vertical stroke of the emitted drawing.
    private struct Stroke {
        let x: Double, y1: Double, y2: Double, width: Double?
    }

    private func render(_ abc: String, config: SVGRenderConfig? = nil)
    -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config ?? self.config).render(score,
                                                                         diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    /// The drawing's vertical strokes.  Read straight out of the SVG: `CeolKitSVGGeometry`
    /// reports staves and bar lines, and a bracket is deliberately neither.
    private func verticalStrokes(in svg: String) -> [Stroke] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"(?: stroke="[^"]*")?(?: stroke-width="([-0-9.]+)")?/)
            .compactMap { match in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      abs(x1 - x2) < 1e-9 else { return nil }
                return Stroke(x: x1, y1: min(y1, y2), y2: max(y1, y2),
                              width: match.5.flatMap { Double($0) })
            }
    }

    /// The strokes standing left of the staves — the brackets, and nothing else.
    private func bracketSpines(_ svg: String, staves: [SystemGeometry]) -> [Stroke] {
        guard let left = staves.first?.left else { return [] }
        return verticalStrokes(in: svg).filter { $0.x < left - 1e-9 }.sorted { $0.x < $1.x }
    }

    /// Three voices, one line of two bars each, with `directive` above the `K:`.
    private func threeVoices(_ directive: String = "") -> String {
        ([
            "X:1", "T:Three Voices", "M:4/4", "L:1/8", directive, "K:D", "V:1", "V:2", "V:3",
            "[V:1] abcd efga | bage dcBA |",
            "[V:2] ABcd efga | bage dcBA |",
            "[V:3] ABcd efga | bage dcBA |",
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Reservation

    @Test("A bracketed system starts right of the margin, and an unbracketed one does not")
    func bracketIsIndentedFromTheMargin() {
        let plain = render(threeVoices()).staves
        let bracketed = render(threeVoices("%%score [1 2 3]")).staves

        #expect(plain.allSatisfy { $0.left == config.margins.left })
        #expect(bracketed.allSatisfy { $0.left > config.margins.left })
        // Every staff of the system starts at the same x: the indent belongs to the system,
        // not to the staff that happens to carry the span.
        #expect(Set(bracketed.map(\.left)).count == 1)
    }

    @Test("The music still ends on the right margin: the indent came out of the line, not off the page")
    func indentIsTakenOutOfTheLine() {
        // `justifyLastSystem` so the one system in each tune is stretched to the full line.
        var config = config
        config.justifyLastSystem = true
        let plain = render(threeVoices(), config: config).staves
        let bracketed = render(threeVoices("%%score [1 2 3]"), config: config).staves

        let rightMargin = config.pageSize.width - config.margins.right
        #expect(plain.allSatisfy { abs($0.right - rightMargin) < 0.5 })
        #expect(bracketed.allSatisfy { abs($0.right - rightMargin) < 0.5 })
    }

    @Test("A plan that only orders the voices reserves nothing")
    func planWithoutSpansReservesNothing() {
        let staves = render(threeVoices("%%score 2 1 3")).staves
        #expect(staves.allSatisfy { $0.left == config.margins.left })
    }

    @Test("The indent scales with the music")
    func indentScalesWithTheTune() {
        let full = render(threeVoices("%%score [1 2 3]")).staves
        let half = render(threeVoices("%%score [1 2 3]\n%%ceolkit:scale 0.5")).staves
        let fullIndent = full[0].left - config.margins.left
        let halfIndent = half[0].left - config.margins.left
        #expect(abs(halfIndent - fullIndent / 2) < 1e-6)
    }

    // MARK: - Drawing

    @Test("The bracket spans the staves it covers, at the face's bracket thickness")
    func bracketSpansTheGroup() throws {
        let (svg, staves) = render(threeVoices("%%score [1 2 3]"))
        let spines = bracketSpines(svg, staves: staves)
        let spine = try #require(spines.first)
        #expect(spines.count == 1)

        let expected = metadata.engravingDefaults.bracketThickness * config.staffSize
        #expect(abs((spine.width ?? 0) - expected) < 1e-3)
        // Top staff line of the first staff to bottom staff line of the last.
        #expect(abs(spine.y1 - staves[0].topY) < 1e-3)
        #expect(abs(spine.y2 - (staves[2].topY + 4 * staves[2].staffLineGap)) < 1e-3)
    }

    @Test("Nothing crosses the left margin, bracket included")
    func nothingCrossesTheLeftMargin() {
        let (svg, staves) = render(threeVoices("%%score [1 2 3]"))
        let spine = bracketSpines(svg, staves: staves)[0]
        let tipWidth = (metadata.glyphBBoxes["bracketTop"]?.width ?? 0) * config.staffSize
        let bracketLeft = spine.x - (spine.width ?? 0) / 2

        #expect(bracketLeft >= config.margins.left - 1e-9)
        // …and the tips, which flare right from the spine, stop short of the staff lines.
        #expect(bracketLeft + tipWidth < staves[0].left)
    }

    @Test("The bracket is drawn with the SMuFL tip glyphs, at the ends of its spine")
    func bracketHasSMuFLTips() throws {
        // `.fontFace`, so the glyphs reach the page as `<text>` and can be read back.
        let score = CeolKitParser().parse(threeVoices("%%score [1 2 3]"), options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try textProbeRenderer().render(score, diagnostics: &diagnostics).joined()
        let staves = try SVGGeometry.pages(from: [svg]).flatMap(\.systems)
        let spine = bracketSpines(svg, staves: staves)[0]
        let bracketLeft = spine.x - (spine.width ?? 0) / 2

        for (glyph, y) in [(SMuFLGlyph.bracketTop, spine.y1), (.bracketBottom, spine.y2)] {
            let tip = try #require(svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/)
                .first { String($0.3) == String(glyph.character) })
            #expect(abs((Double(tip.1) ?? 0) - bracketLeft) < 1e-3)
            #expect(abs((Double(tip.2) ?? 0) - y) < 1e-3)
        }
    }

    @Test("A nested span is drawn inside the outer one, at sub-bracket thickness")
    func nestedSpanIsThinnerAndCloserToTheStaff() throws {
        let (svg, staves) = render(threeVoices("%%score [{1 2} 3]"))
        let spines = bracketSpines(svg, staves: staves)
        #expect(spines.count == 2)
        let (outer, inner) = (spines[0], spines[1])

        let defaults = metadata.engravingDefaults
        #expect(abs((outer.width ?? 0) - defaults.bracketThickness * config.staffSize) < 1e-3)
        #expect(abs((inner.width ?? 0) - defaults.subBracketThickness * config.staffSize) < 1e-3)
        // The outer span covers all three staves; the brace inside it stops at the second.
        #expect(abs(outer.y2 - (staves[2].topY + 4 * staves[2].staffLineGap)) < 1e-3)
        #expect(abs(inner.y2 - (staves[1].topY + 4 * staves[1].staffLineGap)) < 1e-3)
    }

    @Test("A span opening below the top staff is drawn from the staff it opens at")
    func spanOpeningLowerDownIsStillDrawn() throws {
        let (svg, staves) = render(threeVoices("%%score [1 {2 3}]"))
        let spines = bracketSpines(svg, staves: staves)
        #expect(spines.count == 2)
        let inner = try #require(spines.last)
        #expect(abs(inner.y1 - staves[1].topY) < 1e-3)
        #expect(abs(inner.y2 - (staves[2].topY + 4 * staves[2].staffLineGap)) < 1e-3)
    }

    // MARK: - What the bracket must not disturb

    @Test("A bracket is not read back as a bar line")
    func bracketIsNotABarLine() {
        let plain = render(threeVoices()).staves
        let bracketed = render(threeVoices("%%score [1 2 3]")).staves
        #expect(bracketed.map(\.barlineXs.count) == plain.map(\.barlineXs.count))
        #expect(bracketed.allSatisfy { staff in staff.barlineXs.allSatisfy { $0 >= staff.left } })
    }

    @Test("A tune with no plan is drawn exactly as it was before brackets existed")
    func noPlanDrawsNoFurniture() {
        let (svg, staves) = render(threeVoices())
        #expect(bracketSpines(svg, staves: staves).isEmpty)
        #expect(!svg.contains(String(SMuFLGlyph.bracketTop.character)))
    }
}
