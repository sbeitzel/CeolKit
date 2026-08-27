import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #72: a `{ … }` span is drawn as a brace, which is a *stretchy* glyph — the face
/// draws it 3.988 staff spaces tall and it has to reach whatever the staves it joins span.
///
/// The tests read the drawing back in both rendering modes, because the brace is the first
/// thing the renderer draws that the two modes express differently: `.outlines` puts the
/// stretch on the `<use>` transform, `.fontFace` on a group around the `<text>`.
@Suite("Staff Braces")
struct StaffBraceTests {

    private let config = SVGRenderConfig()
    private let metadata = try! BravuraMetadata.load()

    /// The brace as it reaches the page in `.fontFace`: a group carrying the placement and
    /// the two stretch factors, around a `<text>` drawn at the origin.
    private struct DrawnBrace {
        let x: Double, y: Double, xScale: Double, yScale: Double
    }

    private func render(_ abc: String, config: SVGRenderConfig? = nil)
    -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config ?? self.config).render(score,
                                                                         diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    /// The same tune through the `.fontFace` renderer, where the brace can be read back
    /// element by element rather than out of a glyph transform.
    private func renderWithText(_ abc: String, config: SVGRenderConfig? = nil)
    -> (svg: String, staves: [SystemGeometry]) {
        var pinned = config ?? self.config
        pinned.textRendering = .fontFace
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: pinned).render(score, diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    private func braces(in svg: String) -> [DrawnBrace] {
        let brace = String(SMuFLGlyph.brace.character)
        return svg.matches(of: /<g transform="translate\(([-0-9.]+) ([-0-9.]+)\) scale\(([-0-9.]+) ([-0-9.]+)\)">\s*<text [^>]*>(.)<\/text>/)
            .compactMap { match in
                guard String(match.5) == brace,
                      let x = Double(match.1), let y = Double(match.2),
                      let sx = Double(match.3), let sy = Double(match.4) else { return nil }
                return DrawnBrace(x: x, y: y, xScale: sx, yScale: sy)
            }
    }

    /// The `<use>` elements drawing the brace glyph in `.outlines`, as (x, y, sx, sy).
    private func outlineBraces(in svg: String) throws -> [DrawnBrace] {
        let font = try #require(OutlineFontSet.shared().resolve(family: "Bravura", italic: false))
        let gid = try #require(font.font.glyphID(for: SMuFLGlyph.brace.unicodeScalar))
        return svg.matches(of: /<use href="#(bravura-g[0-9]+)"[^>]*transform="translate\(([-0-9.]+) ([-0-9.]+)\) scale\(([-0-9.]+) ([-0-9.]+)\)"/)
            .compactMap { match in
                guard String(match.1) == "bravura-g\(gid)",
                      let x = Double(match.2), let y = Double(match.3),
                      let sx = Double(match.4), let sy = Double(match.5) else { return nil }
                return DrawnBrace(x: x, y: y, xScale: sx, yScale: sy)
            }
    }

    /// The drawing's vertical strokes left of the staves — the bracket spines, which a brace
    /// is deliberately not one of.
    private func spines(_ svg: String, staves: [SystemGeometry]) -> [Double] {
        guard let left = staves.first?.left else { return [] }
        return svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"/)
            .compactMap { match in
                guard let x1 = Double(match.1), let x2 = Double(match.3),
                      abs(x1 - x2) < 1e-9, x1 < left - 1e-9 else { return nil }
                return x1
            }
            .sorted()
    }

    /// `n` voices, one line of two bars each, with `directive` above the `K:`.
    private func voices(_ count: Int, _ directive: String) -> String {
        let heads = (1...count).map { "V:\($0)" }
        let bodies = (1...count).map { "[V:\($0)] abcd efga | bage dcBA |" }
        return (["X:1", "T:Braced", "M:4/4", "L:1/8", directive, "K:D"] + heads + bodies)
            .joined(separator: "\n")
    }

    /// Bottom staff line of the last staff — where a brace's foot belongs.
    private func bottomLine(of staff: SystemGeometry) -> Double {
        staff.topY + 4 * staff.staffLineGap
    }

    // MARK: - Drawing

    @Test("A braced span is drawn as a brace, reaching the outer staff lines of the group")
    func braceSpansTheGroup() throws {
        let (svg, staves) = renderWithText(voices(2, "%%score {1 2}"))
        let brace = try #require(braces(in: svg).first)
        #expect(braces(in: svg).count == 1)

        let natural = try #require(metadata.glyphBBoxes["brace"])
        // The glyph stands on its baseline, so its foot is the group's bottom staff line…
        #expect(abs(brace.y - bottomLine(of: staves[1])) < 1e-3)
        // …and its head, `naturalHeight` scaled, is the top staff line of the first staff.
        let head = brace.y - natural.height * config.staffSize * brace.yScale
        #expect(abs(head - staves[0].topY) < 1e-3)
    }

    @Test("A brace is a glyph, not a spine: nothing is stroked left of the staves")
    func braceDrawsNoSpine() {
        let (braced, bracedStaves) = render(voices(2, "%%score {1 2}"))
        let (bracketed, bracketedStaves) = render(voices(2, "%%score [1 2]"))
        #expect(spines(braced, staves: bracedStaves).isEmpty)
        #expect(spines(bracketed, staves: bracketedStaves).count == 1)
    }

    @Test("The brace stands inside the indent reserved for it, clear of the staves")
    func braceStandsInItsColumn() throws {
        let (svg, staves) = renderWithText(voices(2, "%%score {1 2}"))
        let brace = try #require(braces(in: svg).first)
        let box = try #require(metadata.glyphBBoxes["brace"])

        let ink = (left: brace.x + box.swX * config.staffSize * brace.xScale,
                   right: brace.x + box.neX * config.staffSize * brace.xScale)
        #expect(ink.left >= config.margins.left - 1e-9)
        #expect(ink.right < staves[0].left)
    }

    @Test("The music still ends on the right margin: the brace's indent came out of the line")
    func indentIsTakenOutOfTheLine() {
        var config = config
        config.justifyLastSystem = true
        let staves = render(voices(2, "%%score {1 2}"), config: config).staves
        let rightMargin = config.pageSize.width - config.margins.right
        #expect(staves.allSatisfy { $0.left > config.margins.left })
        #expect(staves.allSatisfy { abs($0.right - rightMargin) < 0.5 })
    }

    // MARK: - Stretch

    @Test("A two-staff brace keeps the face's proportions; a taller one stops thickening")
    func armsThickenWithTheSpanUpToAStaffSpace() throws {
        let box = try #require(metadata.glyphBBoxes["brace"])

        let two = try #require(braces(in: renderWithText(voices(2, "%%score {1 2}")).svg).first)
        // Below the cap the brace is simply drawn larger, at the proportions Bravura drew.
        #expect(abs(two.xScale - two.yScale) < 1e-3)

        let four = try #require(braces(in: renderWithText(voices(4, "%%score {1 2 3 4}")).svg).first)
        #expect(four.yScale > two.yScale)
        // Past it the arms hold at a staff space wide however far the span stretches, which
        // is what keeps a brace over four staves from reading as a slab.
        #expect(four.xScale < four.yScale)
        #expect(abs(box.width * four.xScale - 1.0) < 1e-3)
    }

    @Test("The brace scales with the music")
    func braceScalesWithTheTune() throws {
        let box = try #require(metadata.glyphBBoxes["brace"])
        let full = renderWithText(voices(2, "%%score {1 2}"))
        let half = renderWithText(voices(2, "%%score {1 2}\n%%ceolkit:scale 0.5"))
        let fullBrace = try #require(braces(in: full.svg).first)
        let halfBrace = try #require(braces(in: half.svg).first)

        // The factors are ratios against a natural size stated in staff spaces, so they do
        // not change with the staff size: a half-size tune stretches the brace by the same
        // amount and draws it half as big.
        #expect(abs(halfBrace.xScale - fullBrace.xScale) < 1e-6)
        #expect(abs(halfBrace.yScale - fullBrace.yScale) < 1e-6)

        // Which is what reaches the page — measured in the staff spaces of each tune.
        func ink(_ brace: DrawnBrace, _ staves: [SystemGeometry]) -> (Double, Double) {
            let staffSize = staves[0].staffLineGap
            return (box.width * staffSize * brace.xScale,
                    box.height * staffSize * brace.yScale)
        }
        let (fullWidth, fullHeight) = ink(fullBrace, full.staves)
        let (halfWidth, halfHeight) = ink(halfBrace, half.staves)
        #expect(abs(halfWidth - fullWidth / 2) < 1e-6)
        #expect(abs(halfHeight - fullHeight / 2) < 1e-6)
    }

    @Test("Both rendering modes draw the same brace in the same place")
    func outlineAndFontFaceAgree() throws {
        let abc = voices(3, "%%score {1 2 3}")
        let text = try #require(braces(in: renderWithText(abc).svg).first)
        let outline = try #require(try outlineBraces(in: render(abc).svg).first)
        let font = try #require(OutlineFontSet.shared().resolve(family: "Bravura", italic: false))
        // The outline carries the em-to-point factor in the same transform, and flips out of
        // font design space; the `<text>` route has it in `font-size` instead.
        let em = 4.0 * config.staffSize / font.font.unitsPerEm

        #expect(abs(outline.x - text.x) < 1e-3)
        #expect(abs(outline.y - text.y) < 1e-3)
        #expect(abs(outline.xScale - text.xScale * em) < 1e-5)
        #expect(abs(outline.yScale + text.yScale * em) < 1e-5)
    }

    // MARK: - Alongside brackets

    @Test("A brace nested in a bracket is still a brace, in its own column")
    func nestedBraceIsStillABrace() throws {
        let (svg, staves) = renderWithText(voices(3, "%%score [{1 2} 3]"))
        let brace = try #require(braces(in: svg).first)
        let spine = try #require(spines(svg, staves: staves).first)
        #expect(spines(svg, staves: staves).count == 1)

        // The bracket outside it, the brace inside — the nesting read off the page.
        #expect(brace.x > spine)
        // The brace covers the first two staves, and the bracket all three.
        let natural = try #require(metadata.glyphBBoxes["brace"])
        #expect(abs(brace.y - bottomLine(of: staves[1])) < 1e-3)
        #expect(abs(brace.y - natural.height * config.staffSize * brace.yScale
                    - staves[0].topY) < 1e-3)
    }

    @Test("A tune with no braced span draws no brace, and no group around anything")
    func nothingIsWrappedWhenNothingIsStretched() {
        let svg = render(voices(3, "%%score [1 2 3]")).svg
        #expect(!svg.contains(String(SMuFLGlyph.brace.character)))
        #expect(!svg.contains("<g transform="))
        // Every other glyph is still drawn at one factor on both axes.
        for match in svg.matches(of: /scale\(([-0-9.]+) ([-0-9.]+)\)/) {
            let (sx, sy) = (Double(match.1) ?? 0, Double(match.2) ?? 0)
            #expect(abs(abs(sx) - abs(sy)) < 1e-9)
        }
    }
}

/// The `SVGBuilder` surface the brace needed: a run scaled differently on the two axes, and
/// the group that carries it where a `<text>` element cannot.
@Suite("Anisotropic glyph scaling")
struct StretchedTextTests {

    private let fonts = try! OutlineFontSet.shared()
    /// A glyph Bravura actually draws, so the outline route has an outline to emit.
    private let glyph = String(SMuFLGlyph.brace.character)

    @Test("An unstretched run is written exactly as `text` writes it, in both modes")
    func identityStretchChangesNothing() {
        for rendering in [TextRendering.fontFace, .outlines, .both] {
            var plain = SVGBuilder(textRendering: rendering, fonts: fonts)
            plain.text(glyph, x: 10, y: 20, fontFamily: "Bravura", fontSize: 24)
            var stretched = SVGBuilder(textRendering: rendering, fonts: fonts)
            stretched.stretchedText(glyph, x: 10, y: 20, fontFamily: "Bravura", fontSize: 24,
                                    xScale: 1, yScale: 1)
            #expect(plain.elements == stretched.elements)
        }
    }

    @Test("The `<use>` transform carries the two factors, still flipped out of design space")
    func outlineRunCarriesBothFactors() throws {
        var builder = SVGBuilder(textRendering: .outlines, fonts: fonts)
        builder.stretchedText(glyph, x: 0, y: 0, fontFamily: "Bravura", fontSize: 1000,
                              xScale: 2, yScale: 3)
        let element = try #require(builder.elements.first)
        // `font-size` 1000 against Bravura's 1000-unit em makes the base factor exactly 1.
        #expect(element.contains("scale(2 -3)"))
    }

    @Test("In `.both`, the stretch reaches the outline and the text copy alike")
    func bothModesCarryTheStretch() {
        var builder = SVGBuilder(textRendering: .both, fonts: fonts)
        builder.stretchedText(glyph, x: 10, y: 20, fontFamily: "Bravura", fontSize: 1000,
                              xScale: 2, yScale: 3)
        // The painted outline…
        #expect(builder.elements.contains { $0.hasPrefix("<use ") && $0.contains("scale(2 -3)") })
        // …and the non-painting `<text>` copy that keeps the document selectable, stretched
        // the same way so the two describe the same shape.
        #expect(builder.elements.contains { $0 == "<g transform=\"translate(10 20) scale(2 3)\">" })
        #expect(builder.elements.contains { $0.contains("<text ") && $0.contains("fill=\"none\"") })
    }

    @Test("A stretched `<text>` is drawn at the origin of a group carrying the transform")
    func fontFaceRunIsWrappedInAGroup() {
        var builder = SVGBuilder(textRendering: .fontFace, fonts: fonts)
        builder.stretchedText(glyph, x: 10, y: 20, fontFamily: "Bravura", fontSize: 24,
                              xScale: 2, yScale: 3)
        #expect(builder.elements == [
            "<g transform=\"translate(10 20) scale(2 3)\">",
            "  <text x=\"0\" y=\"0\" font-family=\"Bravura\" font-size=\"24\" fill=\"black\">\(glyph)</text>",
            "</g>",
        ])
    }

    @Test("A group that wraps nothing is not emitted")
    func emptyGroupIsDropped() {
        var builder = SVGBuilder(textRendering: .fontFace, fonts: fonts)
        builder.group(transform: "scale(2 3)") { _ in }
        #expect(builder.elements.isEmpty)
    }

    @Test("A group nests, and its contents are indented inside it")
    func groupsNest() {
        var builder = SVGBuilder(textRendering: .fontFace, fonts: fonts)
        builder.group(transform: "translate(1 2)") { outer in
            outer.group(transform: "scale(2 3)") { $0.comment("inner") }
        }
        #expect(builder.elements == [
            "<g transform=\"translate(1 2)\">",
            "  <g transform=\"scale(2 3)\">",
            "    <!-- inner -->",
            "  </g>",
            "</g>",
        ])
    }
}
