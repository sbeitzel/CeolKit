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
    private let staffSize = SVGRenderConfig().staffSize

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
