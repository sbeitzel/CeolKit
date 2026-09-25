import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #181: stems, flags and beams join where the font's SMuFL anchors say, not at the
/// glyphs' bounding-box edges.
///
/// A stem placed with its centreline on the notehead's edge hangs half outside it, and a
/// flag hung from that centreline starts half a stem to one side of it — a visible step at
/// every join.  Each test reads one join back out of the emitted document and checks it
/// against the anchor in `bravura_metadata.json`, so a regression to the old geometry is off
/// by half a stem thickness (0.36 pt at the default staff size), well outside the tolerance.
@Suite("Stem, flag and beam attachment (#181)")
struct StemAnchorTests {

    private struct Line { let x1, y1, x2, y2, width: Double }
    private struct Glyph { let x, y: Double; let glyph: Character }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().staffSize
    /// SVG coordinates are written to three decimals.
    private let tolerance = 0.002

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private var stemThickness: Double { metadata.engravingDefaults.stemThickness * s }

    private func render(_ body: String) throws -> String {
        let abc = "X:1\nT:Stems\nM:4/4\nL:1/8\nK:C\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        return try textProbeRenderer().render(score).joined()
    }

    private func lines(in svg: String) -> [Line] {
        svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5) else { return nil }
            return Line(x1: x1, y1: y1, x2: x2, y2: y2, width: w)
        }
    }

    private func glyphs(_ glyph: SMuFLGlyph, in svg: String) -> [Glyph] {
        svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/)
            .compactMap { m in
                guard let x = Double(m.1), let y = Double(m.2),
                      let ch = String(m.3).first, ch == glyph.character else { return nil }
                return Glyph(x: x, y: y, glyph: ch)
            }
    }

    /// Vertical lines at `width`: the stems, drawn top to bottom.
    private func stems(in svg: String, width: Double) -> [Line] {
        lines(in: svg).filter { $0.x1 == $0.x2 && abs($0.width - width) < 0.01 }
    }

    private func anchor(_ name: String, on glyph: SMuFLGlyph) throws -> (x: Double, y: Double) {
        try #require(metadata.anchor(name, on: glyph))
    }

    @Test("An up stem sits inside the notehead's right edge, on its stemUpSE anchor")
    func upStemUsesStemUpSE() throws {
        // E is below the middle line, so it stems up.
        let svg = try render("E2")
        let head = try #require(glyphs(.noteheadBlack, in: svg).first)
        let stem = try #require(stems(in: svg, width: stemThickness).first)
        let se = try anchor("stemUpSE", on: .noteheadBlack)

        // The stem's right edge — its centreline plus half its thickness — is the anchor.
        #expect(abs(stem.x1 + stemThickness / 2 - (head.x + se.x * s)) < tolerance)
        // Its bottom is the anchor's height, above the notehead's centre (SVG y is down).
        #expect(abs(stem.y2 - (head.y - se.y * s)) < tolerance)
    }

    @Test("A down stem sits inside the notehead's left edge, on its stemDownNW anchor")
    func downStemUsesStemDownNW() throws {
        // g is above the middle line, so it stems down.
        let svg = try render("g2")
        let head = try #require(glyphs(.noteheadBlack, in: svg).first)
        let stem = try #require(stems(in: svg, width: stemThickness).first)
        let nw = try anchor("stemDownNW", on: .noteheadBlack)

        #expect(abs(stem.x1 - stemThickness / 2 - (head.x + nw.x * s)) < tolerance)
        #expect(abs(stem.y1 - (head.y - nw.y * s)) < tolerance)
    }

    @Test("A half note's stem uses the half notehead's own anchor")
    func halfNoteUsesItsOwnAnchor() throws {
        let svg = try render("E4")
        let head = try #require(glyphs(.noteheadHalf, in: svg).first)
        let stem = try #require(stems(in: svg, width: stemThickness).first)
        let se = try anchor("stemUpSE", on: .noteheadHalf)
        #expect(abs(stem.x1 + stemThickness / 2 - (head.x + se.x * s)) < tolerance)
    }

    @Test("A flag is hung by its own anchor from the stem's left edge and tip",
          arguments: [("E", SMuFLGlyph.flag8thUp), ("E/", .flag16thUp), ("E//", .flag32ndUp),
                      ("g", .flag8thDown), ("g/", .flag16thDown), ("g//", .flag32ndDown)])
    func flagHangsByItsAnchor(note: String, flag: SMuFLGlyph) throws {
        let svg = try render(note)
        let stem = try #require(stems(in: svg, width: stemThickness).first)
        let drawn = try #require(glyphs(flag, in: svg).first)
        let up = flag.rawValue.hasSuffix("Up")
        let join = try anchor(up ? "stemUpNW" : "stemDownSW", on: flag)
        let tipY = up ? stem.y1 : stem.y2

        #expect(abs(drawn.x + join.x * s - (stem.x1 - stemThickness / 2)) < tolerance)
        #expect(abs(drawn.y - join.y * s - tipY) < tolerance)
    }

    @Test("A beam covers its outer stems rather than stopping at their centrelines")
    func beamCoversOuterStems() throws {
        let svg = try render("EFGA")
        let stemLines = stems(in: svg, width: stemThickness).sorted { $0.x1 < $1.x1 }
        let first = try #require(stemLines.first), last = try #require(stemLines.last)
        let beamWidth = metadata.engravingDefaults.beamThickness * s
        let beam = try #require(lines(in: svg).first {
            $0.y1 == $0.y2 && abs($0.width - beamWidth) < 0.01
        })
        #expect(abs(beam.x1 - (first.x1 - stemThickness / 2)) < tolerance)
        #expect(abs(beam.x2 - (last.x1 + stemThickness / 2)) < tolerance)
    }

    @Test("A grace note follows the same anchors at grace scale")
    func graceNoteUsesAnchorsAtItsScale() throws {
        let scale = GraceMetrics.scale
        let graceStem = stemThickness * scale
        let svg = try render("{g}E2")
        let head = try #require(glyphs(.noteheadBlack, in: svg).min { $0.x < $1.x })
        let stem = try #require(stems(in: svg, width: graceStem).first)
        let flag = try #require(glyphs(.flag32ndUp, in: svg).first)
        let se = try anchor("stemUpSE", on: .noteheadBlack)
        let join = try anchor("stemUpNW", on: .flag32ndUp)

        #expect(abs(stem.x1 + graceStem / 2 - (head.x + se.x * s * scale)) < tolerance)
        #expect(abs(stem.y2 - (head.y - se.y * s * scale)) < tolerance)
        #expect(abs(flag.x + join.x * s * scale - (stem.x1 - graceStem / 2)) < tolerance)
        #expect(abs(flag.y - join.y * s * scale - stem.y1) < tolerance)
    }
}
