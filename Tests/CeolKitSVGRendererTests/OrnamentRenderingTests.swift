import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #264: the ornaments are drawn, stacked with the fermata over the note as abcm2ps
/// (8.14, `-g`) stacks them — clear of the note's stem, beam and grace group, nearest the
/// note first in the order they were written, and under the staff for the part whose stems
/// go down on a shared staff.
@Suite("Ornaments (#264)")
struct OrnamentRenderingTests {

    private struct Glyph { let x, y: Double; let glyph: SMuFLGlyph }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize
    /// SVG coordinates are written to three decimals.
    private let tolerance = 0.002

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private func render(_ body: String, header: String = "") throws -> [String] {
        let abc = "X:1\nT:Ornaments\nM:4/4\nL:1/8\n\(header)K:D\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        return try textProbeRenderer().render(score)
    }

    /// Every single-glyph Bravura `<text>` drawn, left to right.
    private func glyphs(in svg: String) -> [Glyph] {
        let byChar = Dictionary(SMuFLGlyph.allCases.map { ($0.character, $0) },
                                uniquingKeysWith: { first, _ in first })
        return svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/)
            .compactMap { m -> Glyph? in
                guard let x = Double(m.1), let y = Double(m.2),
                      let glyph = String(m.3).first.flatMap({ byChar[$0] }) else { return nil }
                return Glyph(x: x, y: y, glyph: glyph)
            }
            .sorted { $0.x < $1.x }
    }

    private func glyphs(_ glyph: SMuFLGlyph, in svg: String) -> [Glyph] {
        glyphs(in: svg).filter { $0.glyph == glyph }
    }

    private func box(_ glyph: SMuFLGlyph) throws -> BravuraMetadata.BoundingBox {
        try #require(metadata.glyphBBoxes[glyph.rawValue])
    }

    /// The glyph's ink, top and bottom, in page coordinates.
    private func ink(_ g: Glyph) throws -> (top: Double, bottom: Double) {
        let b = try box(g.glyph)
        return (g.y - b.neY * s, g.y - b.swY * s)
    }

    private func centreX(_ g: Glyph) throws -> Double {
        let b = try box(g.glyph)
        return g.x + (b.swX + b.neX) / 2 * s
    }

    private func stems(in svg: String) -> [(x: Double, top: Double, bottom: Double)] {
        let width = metadata.engravingDefaults.stemThickness * s
        return svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5), abs(w - width) < 0.01,
                  x1 == x2, y1 != y2 else { return nil }
            return (x1, min(y1, y2), max(y1, y2))
        }
        .sorted { $0.x < $1.x }
    }

    private func staffTops(in svgs: [String]) throws -> [Double] {
        try SVGGeometry.pages(from: svgs).flatMap(\.systems).map(\.topY)
    }

    // MARK: - Drawn at all

    @Test("!trill! and T draw a trill, with or without a grace group in front")
    func trillIsDrawn() throws {
        // The fragment from the issue, and the two spellings on their own.
        let svg = try render("{g}ef/e/ d2 {gef}!trill!e4 | !trill!e4 Te4 |]").joined()
        #expect(glyphs(.ornamentTrill, in: svg).count == 3)
    }

    @Test("Each ornament draws its own glyph", arguments: [
        ("Me4", SMuFLGlyph.ornamentMordent),
        ("!mordent!e4", .ornamentMordent),
        ("!lowermordent!e4", .ornamentMordent),
        ("Pe4", .ornamentShortTrill),
        ("!pralltriller!e4", .ornamentShortTrill),
        ("!uppermordent!e4", .ornamentShortTrill),
        ("!turn!e4", .ornamentTurn),
        ("!invertedturn!e4", .ornamentTurnInverted),
    ])
    func ornamentGlyph(body: String, glyph: SMuFLGlyph) throws {
        let svg = try render(body + " z4 |]").joined()
        #expect(glyphs(glyph, in: svg).count == 1)
    }

    @Test("~ draws a roll: one filled arc over the note")
    func rollIsDrawn() throws {
        let plain = try render("e4 A4 |]").joined()
        let rolled = try render("~e4 ~A4 |]").joined()
        let paths = { (svg: String) in svg.matches(of: /<path d="M[^"]*" fill="black"\/>/).count }
        #expect(paths(rolled) - paths(plain) == 2)
    }

    // MARK: - Placement

    @Test("An ornament is centred over its notehead")
    func trillIsCentred() throws {
        let svg = try render("Te4 z4 |]").joined()
        let trill = try #require(glyphs(.ornamentTrill, in: svg).first)
        let head = try #require(glyphs(.noteheadHalf, in: svg).first)
        #expect(abs(try centreX(trill) - centreX(head)) < tolerance)
    }

    @Test("An ornament stands clear of a stem going up, and of the staff over a stem going down")
    func trillClearsTheNote() throws {
        // A4 stems up, e5 down.
        let svg = try render("TA4 Te4 |]").joined()
        let trills = glyphs(.ornamentTrill, in: svg)
        try #require(trills.count == 2)
        let stems = stems(in: svg)
        try #require(stems.count == 2)
        let staffTop = try #require(try staffTops(in: [svg]).first)

        #expect(try ink(trills[0]).bottom <= stems[0].top - 0.5 * s + tolerance)
        // e5's head sits in the top space, so the staff, not the note, is what it clears.
        #expect(abs(try ink(trills[1]).bottom - (staffTop - s)) < tolerance)
    }

    @Test("A trill clears the grace group written in front of its note")
    func trillClearsGraceGroup() throws {
        // A pipe-style group whose stems reach well over the staff.
        let svg = try render("{gef}!trill!e4 z4 |]", header: "%%ceolkit:pipeformat true\n").joined()
        let trill = try #require(glyphs(.ornamentTrill, in: svg).first)
        let graceTop = try #require(stems(in: svg).map(\.top).min())
        #expect(try ink(trill).bottom < graceTop)
    }

    @Test("Marks stack outward in the order they are written: THe puts the fermata over the trill")
    func marksStack() throws {
        let svg = try render("THe4 HTe4 |]").joined()
        let trills = glyphs(.ornamentTrill, in: svg)
        let fermatas = glyphs(.fermataAbove, in: svg)
        try #require(trills.count == 2 && fermatas.count == 2)

        // Written first, nearest the note; the next a quarter space beyond it.
        let gap = DecorationStack.markGap * s
        #expect(abs(try ink(fermatas[0]).bottom - (ink(trills[0]).top - gap)) < tolerance)
        #expect(abs(try ink(trills[1]).bottom - (ink(fermatas[1]).top - gap)) < tolerance)
    }

    @Test("On a shared staff the part stemmed down sets its marks under the staff")
    func lowerVoiceMarksGoBelow() throws {
        let svgs = try render("""
            [V:1] Te4 He4 |]
            [V:2] TA4 HA4 |]
            """, header: "%%score (1 2)\nV:1\nV:2\n")
        let svg = svgs.joined()
        let trills = glyphs(.ornamentTrill, in: svg)
        try #require(trills.count == 2)
        let staffTop = try #require(try staffTops(in: svgs).first)
        let staffBottom = staffTop + 4 * s

        let above = trills.filter { $0.y < staffTop }
        let below = trills.filter { $0.y > staffBottom }
        #expect(above.count == 1 && below.count == 1)
        // The upper part's fermata keeps its shape; the lower part's turns over.
        #expect(glyphs(.fermataAbove, in: svg).count == 1)
        #expect(glyphs(.fermataBelow, in: svg).allSatisfy { $0.y > staffBottom })
        #expect(glyphs(.fermataBelow, in: svg).count == 1)
    }

    // MARK: - Extended trill

    private func wiggles(in svg: String) -> [(x: Double, y: Double, count: Int)] {
        let wiggle = SMuFLGlyph.wiggleTrill.character
        return svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>([^<]+)<\/text>/)
            .compactMap { m in
                let text = String(m.3)
                guard let x = Double(m.1), let y = Double(m.2),
                      !text.isEmpty, text.allSatisfy({ $0 == wiggle }) else { return nil }
                return (x, y, text.count)
            }
    }

    @Test("!trill( … !trill) draws a wavy line from its first note to short of its last")
    func extendedTrill() throws {
        let svg = try render("!trill(!e2 f2 g2 !trill)!a2 |]").joined()
        let lines = wiggles(in: svg)
        try #require(lines.count == 1)
        let heads = glyphs(.noteheadBlack, in: svg)
        try #require(heads.count == 4)

        let line = lines[0]
        let advance = DecorationStack.wiggleAdvance * s
        let end = line.x + Double(line.count) * advance
        #expect(abs(line.x - (try centreX(heads[0]))) < tolerance)
        // abcm2ps stops it two spaces short of the last note's centre.
        #expect(abs(end - (try centreX(heads[3]) - 2 * s)) <= advance / 2 + tolerance)
        // Over every note it spans.
        let box = try box(.wiggleTrill)
        let bottom = line.y - box.swY * s
        for head in heads.prefix(3) {
            #expect(bottom < (try ink(head).top))
        }
    }

    @Test("An extended trill open at a line break runs to the end of the line and on from the next")
    func extendedTrillAcrossSystems() throws {
        let svg = try render("!trill(!e2 f2 g2 a2 |\nb2 a2 g2 !trill)!f2 |]").joined()
        #expect(wiggles(in: svg).count == 2)
    }

    // MARK: - Room

    @Test("Room is made over the staff for a trill on a high note")
    func roomIsReserved() throws {
        let plain = try #require(try staffTops(in: render("a'4 z4 |]")).first)
        let trilled = try #require(try staffTops(in: render("Ta'4 z4 |]")).first)
        #expect(trilled > plain)
    }
}
