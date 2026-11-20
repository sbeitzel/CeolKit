import Foundation
import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private func parseTune(_ body: String) -> Tune? {
    let abc = "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n\(body)"
    return CeolKitParser().parse(abc, options: .default).score.tunes.first
}

/// Renders `body` as a one-tune score with the renderer's default configuration.
private func renderFirstPage(_ body: String) throws -> String {
    let tune  = try #require(parseTune(body))
    let score = Score(source: .init(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                      dialect: .loose, creator: nil, charset: nil,
                      tunes: [tune], freeText: [], typesetText: [], diagnostics: [])
    return try #require(try SVGRenderer().render(score).first)
}

/// The `d` of the single drawn `<path>` on the page. Glyph outlines live in `<defs>` as
/// `<path id=…>`, so matching on `d=` finds only what is painted.
private func soleDrawnPath(in svg: String) throws -> String {
    let drawn = svg.components(separatedBy: "<path d=\"").dropFirst()
        .compactMap { $0.components(separatedBy: "\"").first }
    #expect(drawn.count == 1, "Expected exactly 1 drawn path, got \(drawn.count)")
    return try #require(drawn.first)
}

/// The numeric coordinates of a path, in order, with the command letters dropped.
private func coordinates(of pathData: String) -> [Double] {
    pathData.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
}

/// Y of a cubic Bézier at its midpoint, from the y of its four control points.
private func midpointY(_ p0: Double, _ c1: Double, _ c2: Double, _ p3: Double) -> Double {
    (p0 + 3 * c1 + 3 * c2 + p3) / 8
}

/// All notes (in order) across all measures of the first voice.
private func allNotes(in tune: Tune) -> [Note] {
    tune.voices.first?.staves.flatMap(\.measures).flatMap { m in
        m.events.compactMap { if case .note(let n) = $0 { n } else { nil } }
    } ?? []
}

// MARK: - Suite

/// Tests that tie and slur arcs connect the correct pair of notes.
///
/// Regression: the semantic pass attributed `)` to the note *following* it in the
/// token stream rather than the note that precedes it.  For `c (A2 | A2) B` this
/// meant B acquired the slur-close and the arc spanned A→B instead of A→A.
@Suite("Tie and slur arc positioning")
struct TieSlurIntegrationTests {

    // MARK: - Parser-level: TieState

    /// `c A2- | A2 B` — the hyphen tie on A2 must mark the *second* A as `.endsTie`,
    /// leaving B with `.none`.
    @Test("Tie: second A gets endsTie, B gets none")
    func tieEndsOnSecondA() throws {
        let tune  = try #require(parseTune("c A2- | A2 B |"))
        let notes = allNotes(in: tune)
        // Expect: c(none), A(startsTie), A(endsTie), B(none)
        #expect(notes.count == 4)
        let c = try #require(notes.first)
        let a1 = try #require(notes.dropFirst(1).first)
        let a2 = try #require(notes.dropFirst(2).first)
        let b  = try #require(notes.dropFirst(3).first)
        #expect(c.pitch.step  == .c && c.ties  == .none)
        #expect(a1.pitch.step == .a && a1.ties == .startsTie)
        #expect(a2.pitch.step == .a && a2.ties == .endsTie)
        #expect(b.pitch.step  == .b && b.ties  == .none)
    }

    // MARK: - Parser-level: SlurState

    /// `c (A2 | A2) B` — the opening `(` belongs to the first A, the closing `)` to
    /// the second A.  B must have no slur state at all.
    @Test("Slur: first A opens, second A closes, B has no slur")
    func slurEndsOnSecondA() throws {
        let tune  = try #require(parseTune("c (A2 | A2) B |"))
        let notes = allNotes(in: tune)
        // Expect: c(none), A(opens:1 closes:0), A(opens:0 closes:1), B(none)
        #expect(notes.count == 4)
        let c  = try #require(notes.first)
        let a1 = try #require(notes.dropFirst(1).first)
        let a2 = try #require(notes.dropFirst(2).first)
        let b  = try #require(notes.dropFirst(3).first)
        #expect(c.pitch.step  == .c && c.slurs  == .none)
        #expect(a1.pitch.step == .a && a1.slurs == SlurState(opens: 1, closes: 0))
        #expect(a2.pitch.step == .a && a2.slurs == SlurState(opens: 0, closes: 1))
        #expect(b.pitch.step  == .b && b.slurs  == .none)
    }

    // MARK: - Renderer-level: exactly one arc, ending at A not B

    /// Rendering `c A2- | A2 B` must produce exactly one drawn `<path d=…>` element
    /// (the tie arc from A to A).  Glyph outlines in `<defs>` are `<path id=…>`,
    /// so matching on `d=` counts only what is actually drawn on the page.
    @Test("Tie renders exactly one arc")
    func tieRendersOneArc() throws {
        let tune  = try #require(parseTune("c A2- | A2 B |"))
        let score = Score(source: .init(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                          dialect: .loose, creator: nil, charset: nil,
                          tunes: [tune], freeText: [], typesetText: [], diagnostics: [])
        let pages = try SVGRenderer().render(score)
        let svg   = try #require(pages.first)
        let pathCount = svg.components(separatedBy: "<path d=").count - 1
        #expect(pathCount == 1, "Expected exactly 1 tie arc, got \(pathCount)")
    }

    /// Rendering `c (A2 | A2) B` must produce exactly one drawn `<path d=…>` element
    /// (the slur arc from A to A).  Glyph outlines in `<defs>` are `<path id=…>`,
    /// so matching on `d=` counts only what is actually drawn on the page.
    @Test("Slur renders exactly one arc")
    func slurRendersOneArc() throws {
        let tune  = try #require(parseTune("c (A2 | A2) B |"))
        let score = Score(source: .init(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                          dialect: .loose, creator: nil, charset: nil,
                          tunes: [tune], freeText: [], typesetText: [], diagnostics: [])
        let pages = try SVGRenderer().render(score)
        let svg   = try #require(pages.first)
        let pathCount = svg.components(separatedBy: "<path d=").count - 1
        #expect(pathCount == 1, "Expected exactly 1 slur arc, got \(pathCount)")
    }
}

// MARK: - Taper

/// SMuFL models ties and slurs as tapered ribbons — `tieEndpointThickness` at the ends,
/// `tieMidpointThickness` in the middle (and the `slur…` pair for slurs). A stroked curve of
/// any single width cannot express that, so the arc is emitted as a closed filled outline.
/// These tests measure the outline it emits against the numbers the font actually publishes.
///
/// The path is `M …  C …  L …  C …  Z`: 16 coordinates, being one boundary of the ribbon,
/// the blunt end cap, and the other boundary traversed backwards.
@Suite("Tie and slur arc taper")
struct TieSlurTaperTests {

    private let metadata = try! BravuraMetadata.load()
    private let staffSize = SVGRenderConfig().scaledStaffSize

    /// Coordinates come out of the emitter rounded to three decimals, and the midpoint
    /// measurement averages eight of them, so anything beyond this is a real discrepancy.
    private let tolerance = 0.01

    /// Boundary A's four y values, then boundary B's, given the 16 path coordinates.
    private func boundaries(_ n: [Double]) -> (a: [Double], b: [Double]) {
        // A: M(n0,n1) C (n2,n3) (n4,n5) (n6,n7)     — start, control, control, end
        // B: L(n8,n9) C (n10,n11) (n12,n13) (n14,n15) — same, traversed back to the start
        (a: [n[1], n[3], n[5], n[7]], b: [n[9], n[11], n[13], n[15]])
    }

    @Test("The arc is a closed filled outline, not a stroked curve")
    func arcIsFilledOutline() throws {
        let svg = try renderFirstPage("c A2- | A2 B |")
        let d   = try soleDrawnPath(in: svg)
        #expect(d.hasSuffix("Z"), "Outline must close: \(d)")
        #expect(d.contains(" L "), "Outline must cap its far end: \(d)")
        // The drawn element itself, not the glyph <defs>, must be filled rather than stroked.
        let element = try #require(svg.components(separatedBy: "<path d=\"").dropFirst().first)
            .components(separatedBy: "/>").first ?? ""
        #expect(element.contains("fill=\"black\""))
        #expect(!element.contains("stroke-width"))
    }

    @Test("A tie measures tieEndpointThickness at each end")
    func tieEndpointsMatchMetadata() throws {
        let n = coordinates(of: try soleDrawnPath(in: try renderFirstPage("c A2- | A2 B |")))
        try #require(n.count == 16)
        let expected = metadata.engravingDefaults.tieEndpointThickness * staffSize
        // Start of boundary A against end of boundary B, then the two halves of the cap.
        #expect(abs(abs(n[1] - n[15]) - expected) < tolerance)
        #expect(abs(abs(n[7] - n[9])  - expected) < tolerance)
    }

    @Test("A tie measures tieMidpointThickness at its middle")
    func tieMidpointMatchesMetadata() throws {
        let n = coordinates(of: try soleDrawnPath(in: try renderFirstPage("c A2- | A2 B |")))
        try #require(n.count == 16)
        let (a, b) = boundaries(n)
        let gap = abs(midpointY(a[0], a[1], a[2], a[3]) - midpointY(b[0], b[1], b[2], b[3]))
        #expect(abs(gap - metadata.engravingDefaults.tieMidpointThickness * staffSize) < tolerance)
    }

    @Test("A slur measures the slur thicknesses, not the tie ones")
    func slurUsesSlurThicknesses() throws {
        let n = coordinates(of: try soleDrawnPath(in: try renderFirstPage("c (A2 | A2) B |")))
        try #require(n.count == 16)
        let (a, b) = boundaries(n)
        let ends = abs(n[1] - n[15])
        let gap  = abs(midpointY(a[0], a[1], a[2], a[3]) - midpointY(b[0], b[1], b[2], b[3]))
        #expect(abs(ends - metadata.engravingDefaults.slurEndpointThickness * staffSize) < tolerance)
        #expect(abs(gap  - metadata.engravingDefaults.slurMidpointThickness * staffSize) < tolerance)
    }

    /// The point of the whole exercise: the middle has to be visibly fatter than the ends.
    /// Bravura's pair is 0.22 against 0.1 — if a future change flattened the shape back to a
    /// constant width, every assertion above could still pass on a face that published equal
    /// values, but this one names the property that makes it a slur.
    @Test("The middle is thicker than the ends")
    func middleIsThickerThanEnds() throws {
        let n = coordinates(of: try soleDrawnPath(in: try renderFirstPage("c A2- | A2 B |")))
        try #require(n.count == 16)
        let (a, b) = boundaries(n)
        let ends = abs(n[1] - n[15])
        let gap  = abs(midpointY(a[0], a[1], a[2], a[3]) - midpointY(b[0], b[1], b[2], b[3]))
        #expect(gap > ends)
    }
}

// MARK: - Which side the arc curves on

/// A tie curves away from its note's stem and a slur follows abcm2ps's `slur_direction`,
/// both decided by the stems as drawn rather than by the staff position alone, and a voice
/// sharing its staff keeps its arcs on its own side of it (#288).
@Suite("Tie and slur arc side")
struct TieSlurArcSideTests {

    /// Every tie or slur drawn on the page, left to right, as whether it curves below its
    /// notes.  An arc is the only drawn path with a curve in it; its start point is its
    /// first y and its first control point the next, and SVG's y grows downward.
    private func arcsBelow(_ abc: String, topToBottom: Bool = false) throws -> [Bool] {
        let score = CeolKitParser().parse(abc, options: .default).score
        let svg = try #require(try SVGRenderer().render(score).first)
        let drawn: [String] = svg.components(separatedBy: "<path d=\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
        var arcs: [(x: Double, y: Double, below: Bool)] = []
        for d in drawn where d.contains(" C ") {
            let n = coordinates(of: d)
            arcs.append((x: n[0], y: n[1], below: n[3] > n[1]))
        }
        arcs.sort { topToBottom ? $0.y < $1.y : $0.x < $1.x }
        return arcs.map(\.below)
    }

    private func tune(_ body: String, preamble: String = "", voices: String = "") -> String {
        "\(preamble)\n\nX:1\nT:Test\nM:4/4\nL:1/8\n\(voices)K:C\n\(body)\n"
    }

    @Test("Below the middle line with stems left alone, ties and slurs curve below")
    func lowNotesAutoStems() throws {
        #expect(try arcsBelow(tune("C2-C2 (DE)F2 |]")) == [true, true])
    }

    @Test("Above the middle line with stems left alone, ties and slurs curve above")
    func highNotesAutoStems() throws {
        #expect(try arcsBelow(tune("e2-e2 (fg)a2 |]")) == [false, false])
    }

    /// The issue's own case: pipe format stems every note down, so a low note's arc goes
    /// over it, away from the stem, not under it where an up stem would have been.
    @Test("%%ceolkit:pipeformat stems low notes down, and their arcs go above")
    func pipeFormatLowNotes() throws {
        let abc = tune("C2-C2 (DE)F2 | F2-F2 (DE)F2 |]",
                       preamble: "%%ceolkit:pipeformat true")
        #expect(try arcsBelow(abc) == [false, false, false, false])
    }

    @Test("A voice's stem=down sends its low notes' arcs above")
    func voiceStemDown() throws {
        let abc = tune("[V:1] C2-C2 (DE)F2 |]", voices: "V:1 stem=down\n")
        #expect(try arcsBelow(abc) == [false, false])
    }

    @Test("A voice's stem=up sends its high notes' arcs below")
    func voiceStemUp() throws {
        let abc = tune("[V:1] e2-e2 (fg)a2 |]", voices: "V:1 stem=up\n")
        #expect(try arcsBelow(abc) == [true, true])
    }

    /// abcm2ps's `slur_direction` reads every note under the slur: one stem down anywhere in
    /// it puts the slur above, even though the note it starts on is stemmed up.
    @Test("A slur over any down-stemmed note goes above, whatever note it starts on")
    func slurSpanWithADownStem() throws {
        #expect(try arcsBelow(tune("(C2 E2 g2 e2) |]")) == [false])
    }

    /// The same rule's other half: nothing stemmed and nothing under the middle line puts
    /// the slur above; a whole note below it puts it below.
    @Test("A slur over stemless notes goes above unless one lies under the middle line")
    func slurOverStemlessNotes() throws {
        #expect(try arcsBelow(tune("(e8 | f8) |]")) == [false])
        #expect(try arcsBelow(tune("(C8 | D8) |]")) == [true])
    }

    /// abcm2ps's `multi`: on a shared staff the upper voice's arcs go above and the lower
    /// voice's below, though that puts each on the side its stems point.
    @Test("On a shared staff the upper voice arcs above and the lower below")
    func sharedStaffVoicesKeepTheirSides() throws {
        // Both voices under the middle line: the upper voice's arcs still go above.
        let low = tune("[V:1] F2-F2 (FG)A2 |]\n[V:2] C2-C2 (CD)E2 |]",
                       preamble: "%%score (1 2)", voices: "V:1\nV:2\n")
        // Both over it: the lower voice's arcs still go below.
        let high = tune("[V:1] f2-f2 (fg)a2 |]\n[V:2] c2-c2 (cd)e2 |]",
                        preamble: "%%score (1 2)", voices: "V:1\nV:2\n")
        // The upper voice's notes lie above the lower's, so its arcs are the top two.
        #expect(try arcsBelow(low, topToBottom: true) == [false, false, true, true])
        #expect(try arcsBelow(high, topToBottom: true) == [false, false, true, true])
    }
}
