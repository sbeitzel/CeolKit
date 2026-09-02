//
//  LyricRenderingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #82: the syllables of a `w:` line, drawn under the notes they were aligned to.
//

import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// What a `w:` line puts on the page (ABC v2.2 §4.18).
///
/// Read out of the emitted SVG rather than off the layout, for the reason the shared-staff
/// suites give: a syllable the layout believes it placed and one that got drawn are two
/// different claims, and only the second is what a singer sees.  Rendered through
/// ``textProbeRenderer`` so the runs arrive as `<text>` with their content intact.
@Suite("Lyrics: drawn under their notes")
struct LyricRenderingTests {

    private func svg(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try textProbeRenderer().render(score, diagnostics: &diagnostics).joined()
    }

    private func tune(_ body: String, _ lyrics: String...) -> String {
        (["X:1", "T:Lyrics", "M:4/4", "L:1/4", "K:C", body] + lyrics.map { "w: \($0)" })
            .joined(separator: "\n") + "\n"
    }

    /// Every run of ordinary text on the page, as (x, y, content).  Bravura runs — the music
    /// itself — are left out: this suite is only ever asking about words.
    private struct TextRun {
        let x: Double, y: Double, content: String
    }

    private func textRuns(in svg: String) -> [TextRun] {
        svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Libertinus Serif"[^>]*>([^<]*)<\/text>/
        ).compactMap { match in
            guard let x = Double(match.1), let y = Double(match.2) else { return nil }
            return TextRun(x: x, y: y, content: String(match.3))
        }
    }

    private func syllables(in svg: String, _ content: String) -> [TextRun] {
        textRuns(in: svg).filter { $0.content == content }
    }

    // MARK: - The syllables reach the page

    @Test("Every syllable of a w: line is drawn")
    func syllablesAreDrawn() throws {
        let page = try svg(tune("CDEF|", "do re mi fa"))
        for syllable in ["do", "re", "mi", "fa"] {
            #expect(!syllables(in: page, syllable).isEmpty, "'\(syllable)' was not drawn")
        }
    }

    @Test("Syllables are drawn below the staff, in the order their notes are")
    func syllablesFollowTheirNotes() throws {
        let page = try svg(tune("CDEF|", "do re mi fa"))
        let placed = ["do", "re", "mi", "fa"].compactMap { syllables(in: page, $0).first }
        guard placed.count == 4 else { Issue.record("Not every syllable was drawn"); return }
        #expect(placed.map(\.x) == placed.map(\.x).sorted(), "Syllables are out of order")
        // The staff itself is drawn as five lines; every syllable sits under the lowest.
        let staffBottom = SVGLineProbe.horizontalLines(in: page).map(\.y).max() ?? 0
        #expect(placed.allSatisfy { $0.y > staffBottom }, "A syllable was drawn on the staff")
    }

    @Test("A syllable is centred under its notehead")
    func syllableIsCentredOnItsNote() throws {
        let page = try svg(tune("C4|", "do"))
        guard let syllable = syllables(in: page, "do").first else {
            Issue.record("The syllable was not drawn"); return
        }
        #expect(page.contains("text-anchor=\"middle\""))
        // The one notehead on the page, in the music face.
        let heads = page.matches(
            of: /<text x="([-0-9.]+)" y="[-0-9.]+" font-family="Bravura"[^>]*>\u{E0A2}<\/text>/
        ).compactMap { Double($0.1) }
        guard let head = heads.first else { Issue.record("No notehead drawn"); return }
        // Centred on the head, so it stands within half a notehead's width of its left edge.
        #expect(abs(syllable.x - head) < 12)
    }

    // MARK: - Verses

    @Test("A second w: line stacks under the first instead of replacing it")
    func versesStack() throws {
        let page = try svg(tune("CDEF|", "do re mi fa", "un deux trois qua-tre"))
        guard let first = syllables(in: page, "do").first,
              let second = syllables(in: page, "un").first else {
            Issue.record("Both verses were expected on the page"); return
        }
        #expect(second.y > first.y, "The second verse is not below the first")
        #expect(abs(second.x - first.x) < 1e-6, "Both verses sit under the same note")
    }

    @Test("A second verse pushes the system below it one line further down")
    func versesPushTheNextSystemDown() throws {
        func systemGap(_ abc: String) throws -> Double {
            let score = CeolKitParser().parse(abc, options: .default).score
            var diagnostics: [Diagnostic] = []
            let pages = try textProbeRenderer().render(score, diagnostics: &diagnostics)
            let systems = try SVGGeometry.pages(from: pages).flatMap(\.systems)
            guard systems.count >= 2 else {
                Issue.record("Expected two systems, got \(systems.count)")
                return 0
            }
            return systems[1].topY - systems[0].topY
        }
        let body = ["CDEF|", "w: do re mi fa", "GABc|"]
        let one = try systemGap((["X:1", "T:Lyrics", "M:4/4", "L:1/4", "K:C"] + body)
            .joined(separator: "\n") + "\n")
        let two = try systemGap((["X:1", "T:Lyrics", "M:4/4", "L:1/4", "K:C",
                                  "CDEF|", "w: do re mi fa", "w: un deux trois quatre",
                                  "GABc|"]).joined(separator: "\n") + "\n")
        #expect(abs(two - one - LyricBand.lineHeight(staffSize: SVGRenderConfig().staffSize)) < 1e-6)
    }

    @Test("A tune with no lyrics draws no words below its staff")
    func tunesWithoutLyricsDrawNoWordsBelowTheStaff() throws {
        // The title is set in the same face, so the test asks only about what stands under
        // the staff — where a syllable would be.
        let page = try svg("X:1\nT:Lyrics\nM:4/4\nL:1/4\nK:C\nCDEF|\n")
        let staffBottom = SVGLineProbe.horizontalLines(in: page).map(\.y).max() ?? 0
        #expect(textRuns(in: page).allSatisfy { $0.y < staffBottom })
    }

    // MARK: - Hyphens and melismas (§4.18)

    @Test("A divided word is joined by a hyphen between its halves")
    func hyphenJoinsADividedWord() throws {
        let page = try svg(tune("CD|", "hel-lo"))
        guard let hel = syllables(in: page, "hel").first,
              let lo = syllables(in: page, "lo").first,
              let hyphen = syllables(in: page, "-").first else {
            Issue.record("Expected 'hel', '-' and 'lo' on the page"); return
        }
        #expect(hyphen.x > hel.x && hyphen.x < lo.x)
        #expect(abs(hyphen.y - hel.y) < 1e-9, "The hyphen is not on the verse's baseline")
    }

    @Test("A melisma draws an extender line from its syllable to the last note holding it")
    func melismaDrawsAnExtender() throws {
        let page = try svg(tune("CDEF|", "long_ _ _"))
        guard let long = syllables(in: page, "long").first else {
            Issue.record("The syllable was not drawn"); return
        }
        let extenders = SVGLineProbe.horizontalLines(in: page).filter {
            abs($0.y - long.y) < 1e-9
        }
        #expect(extenders.count == 1, "Expected one extender on the verse's baseline")
        guard let extender = extenders.first else { return }
        #expect(extender.x1 > long.x, "The extender starts left of its own syllable")
        #expect(extender.x2 > extender.x1)
    }

    @Test("A skipped note carries no syllable and no extender")
    func skipDrawsNothing() throws {
        let page = try svg(tune("CDEF|", "do * mi fa"))
        #expect(syllables(in: page, "*").isEmpty)
        let baseline = syllables(in: page, "do").first?.y ?? 0
        #expect(SVGLineProbe.horizontalLines(in: page).allSatisfy { abs($0.y - baseline) > 1e-9 })
    }

    @Test("A tilde is set as the space it stands for")
    func tildeIsSetAsASpace() throws {
        let page = try svg(tune("CD|", "once~upon now"))
        #expect(!syllables(in: page, "once upon").isEmpty)
        #expect(syllables(in: page, "once~upon").isEmpty)
    }

    // MARK: - Spacing

    @Test("Notes are spaced far enough apart for the syllables under them")
    func columnsWidenForWideSyllables() throws {
        func systemWidth(_ abc: String) throws -> Double {
            let score = CeolKitParser().parse(abc, options: .default).score
            var diagnostics: [Diagnostic] = []
            let pages = try textProbeRenderer().render(score, diagnostics: &diagnostics)
            guard let system = try SVGGeometry.pages(from: pages).flatMap(\.systems).first else {
                Issue.record("Nothing was drawn"); return 0
            }
            return system.right - system.left
        }
        // Same music on the same page: only the length of the words differs.  A single short
        // system is drawn at its natural width, so the widening is visible in the drawing.
        let narrow = try systemWidth(tune("CDEF|", "a b c d"))
        let wide = try systemWidth(tune("CDEF|", "in-com-pre-hen-si-bil-i-ty un-mis-tak-a-bly"))
        #expect(wide > narrow)
    }
}

/// The `<line>` elements of an emitted page — the staff lines, stems, bar lines and lyric
/// extenders, all of which this suite has to tell apart by position.
enum SVGLineProbe {
    struct Line {
        let x1: Double, x2: Double, y: Double
    }

    /// Every horizontal `<line>`, left-to-right.
    static func horizontalLines(in svg: String) -> [Line] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"/)
            .compactMap { match in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      abs(y1 - y2) < 1e-9 else { return nil }
                return Line(x1: min(x1, x2), x2: max(x1, x2), y: y1)
            }
    }
}
