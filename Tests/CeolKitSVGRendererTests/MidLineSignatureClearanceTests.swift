import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #286: a key or time signature changing part way through a line was drawn from the
/// opening bar's anchor, on top of whatever that bar draws to the right of it — the thin
/// line and dots of `[|:` and `|:`, the dots of `::`, the thin line of `[|`.  The margin
/// kept room past all of it; the signature has to start there too.
///
/// End to end — source in, SVG out — because what is wrong is where strokes land on the page.
@Suite("Mid-line signature clears its opening bar")
struct MidLineSignatureClearanceTests {

    private let metadata = try! BravuraMetadata.load()

    private struct Stroke { let x: Double, width: Double }
    private struct Glyph { let x: Double, y: Double, text: String }

    private func render(_ body: String, staff index: Int) -> (svg: String, staff: SystemGeometry) {
        let abc = ["X:1", "T:Signatures", "M:6/8", "L:1/8", "K:G", body].joined(separator: "\n")
        var config = SVGRenderConfig()
        config.textRendering = .both
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config).render(score, diagnostics: &diagnostics)
        let staves = try! SVGGeometry.pages(from: svgs).flatMap(\.systems)
        return (svgs.joined(), staves[index])
    }

    /// Bar-line strokes: vertical, starting on the staff's top line, heavier than a stem.
    private func barStrokes(in svg: String, on staff: SystemGeometry) -> [Stroke] {
        let tolerance = staff.staffLineGap * 0.1
        let staffLineWidth = metadata.engravingDefaults.staffLineThickness * staff.staffLineGap
        return svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"(?: stroke="[^"]*")? stroke-width="([-0-9.]+)"/)
            .compactMap { match -> Stroke? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let width = Double(match.5),
                      abs(x1 - x2) < 1e-9, abs(y1 - staff.topY) < tolerance,
                      width > staffLineWidth else { return nil }
                return Stroke(x: x1, width: width)
            }
    }

    /// Bravura glyphs drawn inside the staff, from the non-painting `<text>` copies.
    private func glyphs(in svg: String, on staff: SystemGeometry) -> [Glyph] {
        svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>([^<]*)<\/text>/)
            .compactMap { match -> Glyph? in
                guard let x = Double(match.1), let y = Double(match.2) else { return nil }
                return Glyph(x: x, y: y, text: String(match.3))
            }
            .filter { $0.y >= staff.topY - staff.staffLineGap && $0.y <= staff.bottomY + staff.staffLineGap }
    }

    /// The signature drawn at the change starts clear of every stroke and dot the bar
    /// before it draws.  `signs` are the glyphs only the change draws (the header is G, 6/8).
    private func expectClear(_ body: String, signs: [SMuFLGlyph], staff index: Int = 0) throws {
        let (svg, staff) = render(body, staff: index)
        let signChars = Set(signs.map { String($0.character) })
        let all = glyphs(in: svg, on: staff)
        let signatureX = try #require(all.filter { signChars.contains($0.text) }.map(\.x).min(),
                                      "no signature drawn for \(body)")
        // Anything of the bar within reach of the signature, right of it included: the next
        // bar line is a whole measure away.
        let reach = signatureX + 2 * staff.staffLineGap
        for stroke in barStrokes(in: svg, on: staff) where stroke.x < reach {
            #expect(stroke.x + stroke.width / 2 < signatureX,
                    "bar stroke at \(stroke.x) reaches the signature at \(signatureX) in \(body)")
        }
        let dot = String(SMuFLGlyph.repeatDot.character)
        let dotWidth = (metadata.glyphBBoxes["repeatDot"]?.width ?? 0.25) * staff.staffLineGap
        for d in all where d.text == dot && d.x < reach {
            #expect(d.x + dotWidth < signatureX,
                    "repeat dot at \(d.x) reaches the signature at \(signatureX) in \(body)")
        }
    }

    @Test(arguments: ["[|:", "|:", "::", "[|", "| [|:", ":|", "|]", "||", "|"])
    func timeSignatureClearsTheBar(bar: String) throws {
        try expectClear("GAB cde | dcB A3 \(bar)[M:2/4] cd ef | gf ed |]",
                        signs: [.timeSig2, .timeSig4])
    }

    @Test(arguments: ["[|:", "::", "[|"])
    func keySignatureClearsTheBar(bar: String) throws {
        try expectClear("GAB cde | dcB A3 \(bar)[K:F] cd ef | gf ed |]",
                        signs: [.accidentalFlat, .accidentalNatural])
    }

    /// At the head of a system, as in the report: the line opens `[|: [M:2/4]`.
    @Test func timeSignatureClearsAStartRepeatOpeningASystem() throws {
        try expectClear("GAB cde | dcB A3 |]\n[|: [M:2/4] cd ef | gf ed :|]",
                        signs: [.timeSig2, .timeSig4], staff: 1)
    }
}
