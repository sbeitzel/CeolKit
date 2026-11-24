import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Where a tie or slur starts and ends against its notes, which is where abcm2ps puts it
/// (#293): `draw_slur` and `draw_note_ties` in its `draw.c`.
///
/// abcm2ps measures in units of a sixth of a staff space, and so do these tests: `u`.
@Suite("Tie and slur end placement")
struct ArcEndPlacementTests {

    private let staffSize = SVGRenderConfig().scaledStaffSize
    private var u: Double { staffSize / 6 }
    private let headWidth: Double
    private let tolerance = 0.01

    init() throws {
        let metadata = try BravuraMetadata.load()
        headWidth = try #require(metadata.glyphBBoxes["noteheadBlack"]).width
            * SVGRenderConfig().scaledStaffSize
    }

    // MARK: - Reading the page

    private struct Head { let x, y: Double; var centreX: Double }
    private struct Stem { let x, top, bottom: Double }
    private struct Arc { let x1, y1, x2, y2: Double }

    private func render(_ body: String) throws -> String {
        let abc = "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n\(body)"
        let score = CeolKitParser().parse(abc, options: .default).score
        return try textProbeRenderer().render(score).joined()
    }

    /// Every notehead, left to right.
    private func heads(in svg: String) -> [Head] {
        let glyphs: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                      SMuFLGlyph.noteheadHalf.character]
        return svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match -> Head? in
            guard let x = Double(match.1), let y = Double(match.2),
                  let glyph = String(match.3).first, glyphs.contains(glyph) else { return nil }
            return Head(x: x, y: y, centreX: x + headWidth / 2)
        }.sorted { $0.x < $1.x }
    }

    /// The stem drawn on `head`: the vertical line beside it.
    private func stem(of head: Head, in svg: String) throws -> Stem {
        let stems = svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"/
        ).compactMap { match -> Stem? in
            guard let x1 = Double(match.1), let y1 = Double(match.2),
                  let x2 = Double(match.3), let y2 = Double(match.4),
                  x1 == x2, x1 > head.x - 1, x1 < head.x + headWidth + 1,
                  min(y1, y2) <= head.y + staffSize, max(y1, y2) >= head.y - staffSize
            else { return nil }
            return Stem(x: x1, top: min(y1, y2), bottom: max(y1, y2))
        }
        return try #require(stems.first, "No stem by the notehead at \(head.x)")
    }

    /// Every arc, by its centre line's two ends.  The ribbon's `d` holds each end twice,
    /// half its end thickness either side of the centre line.
    private func arcs(in svg: String) -> [Arc] {
        let paths: [String] = svg.components(separatedBy: "<path d=\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
        return paths.compactMap { d -> Arc? in
            let n: [Double] = d.split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { Double($0) }
            guard n.count == 16 else { return nil }
            let y1 = (n[1] + n[15]) / 2
            let y2 = (n[7] + n[9]) / 2
            return Arc(x1: n[0], y1: y1, x2: n[6], y2: y2)
        }
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < tolerance }

    /// How far in from each notehead's centre abcm2ps draws a tie between two notes whose
    /// centres are `distance` apart.
    private func tiePull(_ distance: Double) -> Double {
        distance > 20 * u ? 3.5 * u : 1.5 * u
    }

    // MARK: - Slurs

    @Test("Away from the stems, a slur's ends stand 8 units past the noteheads' centres")
    func awayFromTheStems() throws {
        // B and c both stem down, so the slur goes above, on the side away from them.
        let svg = try render("(Bc) |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        try #require(h.count == 2)
        #expect(close(arc.x1, h[0].centreX))
        #expect(close(arc.y1, h[0].y - 8 * u))
        #expect(close(arc.x2, h[1].centreX))
        #expect(close(arc.y2, h[1].y - 8 * u))
    }

    @Test("A slur between neighbouring notes spans their centres, not the gap between them")
    func neighbouringNotes() throws {
        let svg = try render("(Bc) |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        #expect(close(arc.x2 - arc.x1, h[1].centreX - h[0].centreX))
    }

    @Test("Below, away from the stems, the ends stand 8 units under the noteheads")
    func belowAwayFromTheStems() throws {
        // E and F stem up, and lie under the middle line: the slur goes below.
        let svg = try render("(E2F2) |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        #expect(close(arc.y1, h[0].y + 8 * u))
        #expect(close(arc.y2, h[1].y + 8 * u))
    }

    @Test("A slur starting on an unbeamed quarter's stem starts 6 units below its tip")
    func startOnAQuartersStem() throws {
        // G stems up; c stems down, which puts the slur above — on G's stem side.
        let svg = try render("(G2 c2) |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        let tip = try stem(of: h[0], in: svg).top
        #expect(close(arc.x1, h[0].centreX + 5 * u))
        #expect(close(arc.y1, tip + 6 * u))
    }

    @Test("A slur starting on a flagged note's stem starts beside its flag")
    func startOnAFlaggedStem() throws {
        let svg = try render("(G c) z2 |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        let tip = try stem(of: h[0], in: svg).top
        #expect(close(arc.x1, h[0].centreX + 7 * u))
        #expect(close(arc.y1, tip + 3 * u))
    }

    @Test("A slur starting where a beam runs on starts above the beam")
    func startOverARunningBeam() throws {
        // G and A are beamed, stems up; c stems down and sends the slur above.
        let svg = try render("(GA c) z |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        // At the beam: the stem as drawn ends there, not where it would unbeamed.
        let tip = try stem(of: h[0], in: svg).top
        #expect(close(arc.y1, tip - 3 * u))
    }

    @Test("A slur ending where a beam starts ends 6 units below the stem's tip")
    func endAtABeamsStart() throws {
        // c stems down, so the slur goes above, ending on G — the first of the beamed GA.
        let svg = try render("(c G)A z |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        let tip = try stem(of: h[1], in: svg).top
        #expect(close(arc.x2, h[1].centreX + 1 * u))
        #expect(close(arc.y2, tip + 6 * u))
    }

    @Test("A slur ending inside a beam ends 3 units past the beam")
    func endPastTheBeam() throws {
        // c stems down, so the slur goes above, ending on A — the second of the beamed GA,
        // where no beam starts.
        let svg = try render("(c GA) z |")
        let h = heads(in: svg)
        try #require(h.count == 3)
        let arc = try #require(arcs(in: svg).first)
        let tip = try stem(of: h[2], in: svg).top
        #expect(close(arc.x2, h[2].centreX + 1 * u))
        #expect(close(arc.y2, tip - 3 * u))
    }

    @Test("A whole note's ends are placed by its own, wider notehead")
    func wholeNoteCentre() throws {
        let svg = try render("B8- | B8 |")
        let arc = try #require(arcs(in: svg).first)
        let metadata = try BravuraMetadata.load()
        let whole = try #require(metadata.glyphBBoxes["noteheadWhole"]).width * staffSize
        let xs = svg.matches(
            of: /<text x="([-0-9.]+)" y="[-0-9.]+" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { m -> Double? in
            String(m.2).first == SMuFLGlyph.noteheadWhole.character ? Double(m.1) : nil
        }.sorted()
        try #require(xs.count == 2)
        let (c1, c2) = (xs[0] + whole / 2, xs[1] + whole / 2)
        let pull = tiePull(c2 - c1)
        #expect(close(arc.x1, c1 + pull))
        #expect(close(arc.x2, c2 - pull))
    }

    // MARK: - Ties

    @Test("A tie runs at the noteheads' centre height, drawn in from their centres",
          arguments: ["B-B |", "B4-B4 |", "B4- | B4 z4 |"])
    func tieEnds(_ body: String) throws {
        let svg = try render(body)
        let h = heads(in: svg)
        try #require(h.count == 2)
        let arc = try #require(arcs(in: svg).first)
        let pull = tiePull(h[1].centreX - h[0].centreX)
        #expect(close(arc.y1, h[0].y))
        #expect(close(arc.y2, h[1].y))
        #expect(close(arc.x1, h[0].centreX + pull))
        #expect(close(arc.x2, h[1].centreX - pull))
    }

    @Test("Both of abcm2ps's pulls are reached: close notes, and notes far apart")
    func bothPulls() throws {
        let distances = try ["B-B |", "B4- | B4 z4 |"].map { body -> Double in
            let h = heads(in: try render(body))
            try #require(h.count == 2)
            return h[1].centreX - h[0].centreX
        }
        #expect(distances.min()! <= 20 * u)
        #expect(distances.max()! > 20 * u)
    }

    @Test("A tie from a dotted note on a line starts clear of the dot above it")
    func tieClearsTheDot() throws {
        // B sits on the middle line, so its dot is raised into the space above, and B's
        // tie curves away from its down stem: above, into the dot.
        let svg = try render("B3-B |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        #expect(close(arc.x1, h[0].centreX + tiePull(h[1].centreX - h[0].centreX) + 6 * u))
    }

    @Test("A tie from a dotted note in a space is not moved: its dot is not on the arc")
    func tieInASpaceIsNotMoved() throws {
        let svg = try render("c3-c |")
        let h = heads(in: svg)
        let arc = try #require(arcs(in: svg).first)
        #expect(close(arc.x1, h[0].centreX + tiePull(h[1].centreX - h[0].centreX)))
    }
}
