import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private func parseTune(_ body: String) -> Tune? {
    let abc = "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n\(body)"
    return CeolKitParser().parse(abc, options: .default).score.tunes.first
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

    /// Rendering `c A2- | A2 B` must produce exactly one SVG `<path>` element
    /// (the tie arc from A to A).
    @Test("Tie renders exactly one arc")
    func tieRendersOneArc() throws {
        let tune  = try #require(parseTune("c A2- | A2 B |"))
        let score = Score(source: .init(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                          dialect: .loose, creator: nil, charset: nil,
                          tunes: [tune], freeText: [], typesetText: [], diagnostics: [])
        let pages = try SVGRenderer().render(score)
        let svg   = try #require(pages.first)
        let pathCount = svg.components(separatedBy: "<path").count - 1
        #expect(pathCount == 1, "Expected exactly 1 tie arc, got \(pathCount)")
    }

    /// Rendering `c (A2 | A2) B` must produce exactly one SVG `<path>` element
    /// (the slur arc from A to A).
    @Test("Slur renders exactly one arc")
    func slurRendersOneArc() throws {
        let tune  = try #require(parseTune("c (A2 | A2) B |"))
        let score = Score(source: .init(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                          dialect: .loose, creator: nil, charset: nil,
                          tunes: [tune], freeText: [], typesetText: [], diagnostics: [])
        let pages = try SVGRenderer().render(score)
        let svg   = try #require(pages.first)
        let pathCount = svg.components(separatedBy: "<path").count - 1
        #expect(pathCount == 1, "Expected exactly 1 slur arc, got \(pathCount)")
    }
}
