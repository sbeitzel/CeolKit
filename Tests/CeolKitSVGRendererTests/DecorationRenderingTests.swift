import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #264: the decorations are drawn where abcm2ps (8.14, `-g`) draws them.  Staccato
/// and tenuto against the notehead away from the stem; the accent outside the staff away
/// from the stem; the ornaments, fermata, marcato and wedge over the note clear of its stem,
/// beam and grace group, stacked in the order written; on a shared staff, the part stemmed
/// down sets its marks under the staff.
@Suite("Decorations (#264)")
struct DecorationRenderingTests {

    private struct Glyph { let x, y: Double; let glyph: SMuFLGlyph }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize
    /// SVG coordinates are written to three decimals.
    private let tolerance = 0.002

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private func render(_ body: String, header: String = "", key: String = "D") throws -> [String] {
        let abc = "X:1\nT:Decorations\nM:4/4\nL:1/8\n\(header)K:\(key)\n\(body)\n"
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

    private func centreY(_ g: Glyph) throws -> Double {
        let b = try box(g.glyph)
        return g.y - (b.neY + b.swY) / 2 * s
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

    @Test("Each ornament, bowing and technique mark and fingering draws its own glyph", arguments: [
        ("Me4", SMuFLGlyph.ornamentMordent),
        ("!mordent!e4", .ornamentMordent),
        ("!lowermordent!e4", .ornamentMordent),
        ("Pe4", .ornamentShortTrill),
        ("!pralltriller!e4", .ornamentShortTrill),
        ("!uppermordent!e4", .ornamentShortTrill),
        ("!turn!e4", .ornamentTurn),
        ("!invertedturn!e4", .ornamentTurnInverted),
        ("ue4", .stringsUpBow),
        ("!upbow!e4", .stringsUpBow),
        ("ve4", .stringsDownBow),
        ("!downbow!e4", .stringsDownBow),
        ("!open!e4", .stringsHarmonic),
        ("!snap!e4", .pluckedSnapPizzicatoAbove),
        ("!thumb!e4", .stringsThumbPosition),
        ("!+!e4", .pluckedLeftHandPizzicato),
        ("!plus!e4", .pluckedLeftHandPizzicato),
        ("!0!e4", .fingering0),
        ("!1!e4", .fingering1),
        ("!2!e4", .fingering2),
        ("!3!e4", .fingering3),
        ("!4!e4", .fingering4),
        ("!5!e4", .fingering5),
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

    // MARK: - Articulations

    @Test("A staccato dot sits in the next space out from the head, away from the stem")
    func staccatoAwayFromStem() throws {
        // c (third space) stems down: dot in the top space.  A (second space) stems up: dot
        // under the bottom line.  A note on a line half fills the space next to it, so the
        // dot goes one further: G (second line) stems up, dot in the space under the staff;
        // d (fourth line) stems down, dot in the space over it.
        let svgs = try render(".c2 .A2 .G2 .d2 |]", key: "C")
        let svg = svgs.joined()
        let staffTop = try #require(try staffTops(in: svgs).first)
        let dots = glyphs(in: svg).filter {
            $0.glyph == .articStaccatoAbove || $0.glyph == .articStaccatoBelow
        }
        try #require(dots.count == 4)
        let y = { (position: Int) in staffTop + Double(8 - position) / 2 * s }

        #expect(dots[0].glyph == .articStaccatoAbove)
        #expect(abs(try centreY(dots[0]) - y(7)) < tolerance)
        #expect(dots[1].glyph == .articStaccatoBelow)
        #expect(abs(try centreY(dots[1]) - y(1)) < tolerance)
        #expect(dots[2].glyph == .articStaccatoBelow)
        #expect(abs(try centreY(dots[2]) - y(-1)) < tolerance)
        #expect(dots[3].glyph == .articStaccatoAbove)
        #expect(abs(try centreY(dots[3]) - y(9)) < tolerance)
    }

    @Test("A tenuto is placed as a staccato is")
    func tenutoAwayFromStem() throws {
        let svg = try render("!tenuto!c2 !tenuto!A2 z4 |]", key: "C").joined()
        #expect(glyphs(.articTenutoAbove, in: svg).count == 1)
        #expect(glyphs(.articTenutoBelow, in: svg).count == 1)
    }

    @Test("An accent stands outside the staff, away from the stem")
    func accentOutsideStaff() throws {
        let svgs = try render("Lc2 LA2 !>!c2 !emphasis!A2 |]", key: "C")
        let svg = svgs.joined()
        let staffTop = try #require(try staffTops(in: svgs).first)
        let above = glyphs(.articAccentAbove, in: svg)
        let below = glyphs(.articAccentBelow, in: svg)
        #expect(above.count == 2 && below.count == 2)
        for accent in above {
            #expect(try ink(accent).bottom <= staffTop - s + tolerance)
        }
        for accent in below {
            #expect(try ink(accent).top >= staffTop + 5 * s - tolerance)
        }
    }

    @Test("Marcato and wedge go over the note, clear of a stem going up")
    func marcatoAndWedgeOverTheNote() throws {
        let svg = try render("!^!A2 !wedge!A2 z4 |]", key: "C").joined()
        let marcato = try #require(glyphs(.articMarcatoAbove, in: svg).first)
        let wedge = try #require(glyphs(.articStaccatissimoWedgeAbove, in: svg).first)
        let stems = stems(in: svg)
        try #require(stems.count == 2)
        #expect(try ink(marcato).bottom <= stems[0].top - 0.5 * s + tolerance)
        #expect(try ink(wedge).bottom <= stems[1].top - 0.5 * s + tolerance)
    }

    @Test("A staccato goes nearest the note, whatever order it was written in")
    func nearMarksFirst() throws {
        let svg = try render(".Tc2 T.c2 z4 |]", key: "C").joined()
        let dots = glyphs(.articStaccatoAbove, in: svg)
        let trills = glyphs(.ornamentTrill, in: svg)
        try #require(dots.count == 2 && trills.count == 2)
        for (dot, trill) in zip(dots, trills) {
            #expect(try ink(trill).bottom < ink(dot).top)
        }
        #expect(abs(dots[0].y - dots[1].y) < tolerance)
        #expect(abs(trills[0].y - trills[1].y) < tolerance)
    }

    @Test("On a shared staff the upper part's staccato goes over its stem")
    func staccatoOverUpperVoiceStem() throws {
        let svgs = try render("""
            [V:1] .c4 z4 |]
            [V:2] A4 z4 |]
            """, header: "%%score (1 2)\nV:1\nV:2\n", key: "C")
        let svg = svgs.joined()
        let dot = try #require(glyphs(.articStaccatoAbove, in: svg).first)
        let stem = try #require(stems(in: svg).min { $0.top < $1.top })
        #expect(try ink(dot).bottom <= stem.top - 0.5 * s + tolerance)
        #expect(abs(try centreX(dot) - stem.x) < tolerance)
    }

    // MARK: - Bowing, technique and fingering

    @Test("Bowing marks go over the note, clear of a stem going up")
    func bowingOverTheNote() throws {
        // A stems up, c down; both bows stand over the note either way, as in abcm2ps.
        let svgs = try render("uA2 vc2 vA2 uc2 |]", key: "G")
        let svg = svgs.joined()
        let staffTop = try #require(try staffTops(in: svgs).first)
        let bows = glyphs(in: svg).filter { $0.glyph == .stringsUpBow || $0.glyph == .stringsDownBow }
        let stems = stems(in: svg)
        try #require(bows.count == 4 && stems.count == 4)
        for (bow, stem) in zip(bows, stems) {
            #expect(try ink(bow).bottom <= min(staffTop - s, stem.top - 0.5 * s) + tolerance)
        }
    }

    @Test("Fingerings stack outward in the order written, with the other marks")
    func fingeringsStack() throws {
        let svg = try render("!3!!1!c2 uTc2 z4 |]", key: "G").joined()
        let three = try #require(glyphs(.fingering3, in: svg).first)
        let one = try #require(glyphs(.fingering1, in: svg).first)
        let bow = try #require(glyphs(.stringsUpBow, in: svg).first)
        let trill = try #require(glyphs(.ornamentTrill, in: svg).first)
        let gap = DecorationStack.markGap * s
        #expect(abs(try ink(one).bottom - (ink(three).top - gap)) < tolerance)
        #expect(abs(try ink(trill).bottom - (ink(bow).top - gap)) < tolerance)
    }

    // MARK: - Dynamics and hairpins

    /// Hairpin strokes, in drawing order: two per hairpin.  Bar lines and ledger lines are
    /// as thick, but upright or level; only a hairpin's strokes slant.
    private func hairpinLines(in svg: String) -> [(x1: Double, y1: Double, x2: Double, y2: Double)] {
        let width = DynamicsBand.thickness * s
        return svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5), abs(w - width) < 0.01,
                  x1 != x2, y1 != y2 else { return nil }
            return (x1, y1, x2, y2)
        }
    }

    private func dynamicGlyphs(in svg: String) -> [Glyph] {
        let all: Set<SMuFLGlyph> = [.dynamicPPP, .dynamicPP, .dynamicPiano, .dynamicMP, .dynamicMF,
                                    .dynamicForte, .dynamicFF, .dynamicFFF, .dynamicSforzato]
        return glyphs(in: svg).filter { all.contains($0.glyph) }
    }

    @Test("Each dynamic draws its own glyph", arguments: [
        ("!ppp!", SMuFLGlyph.dynamicPPP), ("!pp!", .dynamicPP), ("!p!", .dynamicPiano),
        ("!mp!", .dynamicMP), ("!mf!", .dynamicMF), ("!f!", .dynamicForte),
        ("!ff!", .dynamicFF), ("!fff!", .dynamicFFF), ("!sfz!", .dynamicSforzato),
    ])
    func dynamicGlyph(mark: String, glyph: SMuFLGlyph) throws {
        let svg = try render(mark + "G4 z4 |]", key: "G").joined()
        #expect(glyphs(glyph, in: svg).count == 1)
    }

    @Test("Dynamics stand under the staff on one line, beyond the lowest note they pass")
    func dynamicsAlignUnderTheStaff() throws {
        // The low B, sets the line for all three, as `%%dynalign` does in abcm2ps.
        let svgs = try render("!p!G2 !mf!B,2 !f!d'2 c'2 |]", key: "G")
        let svg = svgs.joined()
        let staffBottom = try #require(try staffTops(in: svgs).first) + 4 * s
        let dynamics = dynamicGlyphs(in: svg)
        try #require(dynamics.count == 3)
        #expect(Set(dynamics.map(\.y)).count == 1)
        let lowHead = try #require(glyphs(.noteheadBlack, in: svg).max { $0.y < $1.y })
        for dynamic in dynamics {
            #expect(try ink(dynamic).top > ink(lowHead).bottom)
            #expect(dynamic.y > staffBottom)
        }
    }

    @Test("A dynamic is centred on its note")
    func dynamicIsCentred() throws {
        let svg = try render("!mf!G4 z4 |]", key: "G").joined()
        let dynamic = try #require(glyphs(.dynamicMF, in: svg).first)
        let head = try #require(glyphs(.noteheadHalf, in: svg).first)
        #expect(abs(try centreX(dynamic) - centreX(head)) < tolerance)
    }

    @Test("A voice with lyrics sets its dynamics over the staff, beyond the chord symbols, on every line")
    func dynamicsOverAVoiceWithWords() throws {
        // The words are only under the second line; abcm2ps decides by the whole tune.
        let svgs = try render("""
            "G"!p!G4 A4 |
            "D"!f!d4 e4 |]
            w:la la
            """, key: "G")
        let svg = svgs.joined()
        let tops = try staffTops(in: svgs)
        try #require(tops.count == 2)
        let dynamics = dynamicGlyphs(in: svg)
        try #require(dynamics.count == 2)
        let chordSymbols = svg.matches(of: /<text x="[-0-9.]+" y="([-0-9.]+)" font-family="Libertinus Serif"[^>]*>[GD]<\/text>/)
            .compactMap { Double($0.1) }.sorted()
        try #require(chordSymbols.count == 2)
        for (line, dynamic) in dynamics.sorted(by: { $0.y < $1.y }).enumerated() {
            #expect(dynamic.y < tops[line])
            #expect(try ink(dynamic).bottom < chordSymbols[line] - 0.5 * s)
        }
    }

    @Test("A crescendo opens from its start to short of the dynamic on its end note")
    func crescendoShape() throws {
        let svg = try render("!p!!<(!G2 A2 B2 !<)!!f!c2 |]", key: "G").joined()
        let lines = hairpinLines(in: svg)
        try #require(lines.count == 2)
        let piano = try #require(glyphs(.dynamicPiano, in: svg).first)
        let forte = try #require(glyphs(.dynamicForte, in: svg).first)
        let (upper, lower) = lines[0].y2 < lines[1].y2 ? (lines[0], lines[1]) : (lines[1], lines[0])

        // Closed at the left, open by the full opening at the right.
        #expect(abs(upper.y1 - lower.y1) < tolerance)
        #expect(abs((lower.y2 - upper.y2) - DynamicsBand.opening * s) < tolerance)
        // Clear of both dynamics, on their line.
        let pianoBox = try box(.dynamicPiano), forteBox = try box(.dynamicForte)
        #expect(upper.x1 >= piano.x + pianoBox.neX * s)
        #expect(upper.x2 <= forte.x + forteBox.swX * s)
        #expect(abs((upper.y2 + lower.y2) / 2 - (piano.y - DynamicsBand.baselineOffset * s)) < tolerance)
    }

    @Test("A diminuendo closes at its right; !crescendo(! and !diminuendo(! spell the hairpins too")
    func diminuendoShape() throws {
        let svg = try render("!diminuendo(!G2 A2 B2 !diminuendo)!c2 !crescendo(!d2 e2 f2 !crescendo)!g2 |]",
                             key: "G").joined()
        let lines = hairpinLines(in: svg)
        try #require(lines.count == 4)
        let dim = lines.prefix(2), cresc = lines.suffix(2)
        #expect(abs(dim.first!.y2 - dim.last!.y2) < tolerance)
        #expect(abs(abs(dim.first!.y1 - dim.last!.y1) - DynamicsBand.opening * s) < tolerance)
        #expect(abs(cresc.first!.y1 - cresc.last!.y1) < tolerance)
    }

    @Test("A hairpin is never shorter than abcm2ps's 20 points")
    func shortestHairpin() throws {
        let svg = try render("!<(!G !<)!A B2 c4 |]", key: "G").joined()
        let line = try #require(hairpinLines(in: svg).first)
        #expect(line.x2 - line.x1 >= DynamicsBand.shortest * s - tolerance)
    }

    @Test("A hairpin open at a line break runs to the end of the line and on, part open, from the next")
    func hairpinAcrossLines() throws {
        let svg = try render("G2 A2 !<(!B2 c2 |\nd2 e2 !<)!f4 |]", key: "G").joined()
        let lines = hairpinLines(in: svg)
        try #require(lines.count == 4)
        let first = lines.prefix(2), second = lines.suffix(2)
        // The first part closes at its start; the second starts part open.
        #expect(abs(first.first!.y1 - first.last!.y1) < tolerance)
        #expect(abs(abs(second.first!.y1 - second.last!.y1) - DynamicsBand.continuedOpening * s) < tolerance)
    }

    @Test("On a shared staff the upper part's dynamics go over it and the lower part's under it")
    func dynamicsOnASharedStaff() throws {
        let svgs = try render("""
            [V:1] !f!d4 e4 |]
            [V:2] !p!G4 A4 |]
            """, header: "%%score (1 2)\nV:1\nV:2\n", key: "G")
        let svg = svgs.joined()
        let top = try #require(try staffTops(in: svgs).first)
        let forte = try #require(glyphs(.dynamicForte, in: svg).first)
        let piano = try #require(glyphs(.dynamicPiano, in: svg).first)
        #expect(forte.y < top)
        #expect(piano.y > top + 4 * s)
    }

    @Test("A dynamic on a rest is drawn")
    func dynamicOnARest() throws {
        let svg = try render("!p!z4 G4 |]", key: "G").joined()
        #expect(glyphs(.dynamicPiano, in: svg).count == 1)
    }

    @Test("Room is made under the staff for its dynamics")
    func dynamicsRoomIsReserved() throws {
        let plain = try staffTops(in: render("G4 A4 |\nB4 c4 |]", key: "G"))
        let marked = try staffTops(in: render("!p!G4 A4 |\nB4 c4 |]", key: "G"))
        try #require(plain.count == 2 && marked.count == 2)
        #expect(marked[1] - marked[0] > plain[1] - plain[0])
    }

    // MARK: - Arpeggio

    private func arpeggios(in svg: String) -> [(x: Double, y: Double, count: Int)] {
        let wiggle = SMuFLGlyph.wiggleArpeggiatoUp.character
        return svg.matches(of: /<g transform="rotate\(-90 ([-0-9.]+) ([-0-9.]+)\)">\s*<text [^>]*>([^<]+)<\/text>/)
            .compactMap { m in
                let text = String(m.3)
                guard let x = Double(m.1), let y = Double(m.2),
                      text.allSatisfy({ $0 == wiggle }) else { return nil }
                return (x, y, text.count)
            }
    }

    @Test("!arpeggio! draws a wavy line up the left of the chord, past both outer heads")
    func arpeggioSpansTheChord() throws {
        let svg = try render("!arpeggio![CEGc]4 z4 |]", key: "C").joined()
        let lines = arpeggios(in: svg)
        try #require(lines.count == 1)
        let heads = glyphs(.noteheadHalf, in: svg)
        try #require(heads.count == 4)
        let line = lines[0]
        let width = DecorationStack.arpeggioWidth * s
        let length = Double(line.count) * DecorationStack.arpeggioAdvance * s

        // Left of every head, and reaching from below the lowest to above the highest.
        #expect(line.x <= heads.map(\.x).min()! - DecorationStack.arpeggioHeadGap * s + tolerance)
        #expect(line.x - width > heads[0].x - 3 * s)
        #expect(line.y > heads.map(\.y).max()!)
        #expect(line.y - length < heads.map(\.y).min()! - 0.5 * s)
    }

    @Test("An arpeggio stands clear of the chord's accidentals")
    func arpeggioClearsAccidentals() throws {
        let svg = try render("!arpeggio![^ce]4 z4 |]", key: "C").joined()
        let line = try #require(arpeggios(in: svg).first)
        let sharp = try #require(glyphs(.accidentalSharp, in: svg).first)
        let sharpLeft = sharp.x + (try box(.accidentalSharp)).swX * s
        #expect(line.x <= sharpLeft - DecorationStack.arpeggioAccidentalGap * s + tolerance)
    }

    @Test("Room is made in front of a chord for its arpeggio")
    func arpeggioRoomIsReserved() throws {
        let headGap = { (body: String) throws -> Double in
            let heads = self.glyphs(in: try self.render(body, key: "C").joined())
                .filter { $0.glyph == .noteheadBlack }
            return heads.last!.x - heads.first!.x
        }
        let plain = try headGap("c2 [ce]2 z4 |]")
        let arpeggiated = try headGap("c2 !arpeggio![ce]2 z4 |]")
        #expect(arpeggiated > plain)
    }
}
