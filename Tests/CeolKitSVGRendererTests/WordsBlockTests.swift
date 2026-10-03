//
//  WordsBlockTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #187: `W:` words are printed as a block below the tune (ABC v2.2 §5, §6.1.3).
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("W: words print below the tune (#187)")
struct WordsBlockTests {

    private func tune(words: [String], header: String = "", title: String = "t") -> String {
        "X:1\nT:\(title)\n\(header)K:C\n\"Am\"C D E F|]\n"
            + words.map { "W:\($0)\n" }.joined()
    }

    private func render(_ abc: String) throws -> RenderedDocument {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score)
    }

    /// The rows the words drew on each page: every left-aligned row at the margin in
    /// the words' size.
    private func wordRows(_ layout: ResolvedLayout) -> [[ResolvedTitleRow.Item]] {
        layout.pages.map { page in
            page.titleRows.flatMap(\.items).filter {
                $0.anchor == .start && $0.fontSize == WordsBlock.fontSize
                    && $0.x == layout.margins.left
            }
        }
    }

    @Test("The issue's reproduction prints \"hello there\"")
    func reproduction() throws {
        let abc = "X:1\nT:t\nK:C\n\"Am\"C|]\nW:hello there\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        let svg = try textProbeRenderer().render(score).joined()
        #expect(svg.contains(">hello there</text>"))
    }

    @Test("Lines print in order, left-aligned, below the last system")
    func linesBelowTheMusic() throws {
        let layout = try render(tune(words: ["one", "two", "three"])).layout
        let rows = wordRows(layout)[0]
        #expect(rows.map(\.text) == ["one", "two", "three"])
        let baselines = rows.map(\.baselineY)
        #expect(baselines == baselines.sorted())
        let system = try #require(layout.pages[0].systems.last)
        #expect(baselines[0] > system.origin.y + system.totalHeight)
    }

    @Test("A blank W: takes a line's height and draws nothing")
    func blankLineTakesSpace() throws {
        let rows = wordRows(try render(tune(words: ["one", "", "two"])).layout)[0]
        #expect(rows.map(\.text) == ["one", "two"])
        #expect(abs(rows[1].baselineY - rows[0].baselineY - 2 * WordsBlock.lineHeight) < 1e-9)
    }

    @Test("Spacing inside a line survives into the SVG")
    func spacingIsPreserved() throws {
        let score = CeolKitParser().parse(tune(words: ["  indented   twice"]),
                                          options: .default).score
        let svg = try textProbeRenderer().render(score).joined()
        #expect(svg.contains(#"xml:space="preserve""#))
        // The one space after the colon is the separator; the rest is the writer's.
        #expect(svg.contains("> indented   twice</text>"))
    }

    @Test("Text with no runs of spaces is written as before")
    func ordinaryTextUnmarked() throws {
        let score = CeolKitParser().parse(tune(words: ["plain words"]), options: .default).score
        let svg = try textProbeRenderer().render(score).joined()
        #expect(!svg.contains("xml:space"))
    }

    @Test("%%writefields W false suppresses the words")
    func writeFieldsSuppresses() throws {
        let layout = try render(tune(words: ["hidden"], header: "%%writefields W false\n")).layout
        #expect(wordRows(layout).allSatisfy { $0.isEmpty })
    }

    @Test("A long set of words carries over the page break")
    func wordsBreakAcrossPages() throws {
        let lines = (1...80).map { "line \($0)" }
        let layout = try render(tune(words: lines)).layout
        let rows = wordRows(layout)
        #expect(layout.pages.count == 2)
        #expect(rows.flatMap { $0 }.map(\.text) == lines)
        for (page, pageRows) in zip(layout.pages, rows) {
            let height = (page.pageSize ?? layout.pageSize).height
            #expect(pageRows.allSatisfy { $0.baselineY < height - layout.margins.bottom })
        }
        // The second page's words start at its top, not where the first page left off.
        let first = try #require(rows[1].first)
        #expect(first.baselineY < layout.margins.top + WordsBlock.lineHeight)
    }

    @Test("The next tune starts below the words")
    func nextTuneClearsTheWords() throws {
        let abc = tune(words: ["first tune's words", "second line"])
            + "\n" + tune(words: [], title: "Second")
        let document = try render(abc)
        let rows = wordRows(document.layout)[0]
        let last = try #require(rows.last)
        #expect(document.placements[1].pageIndex == 0)
        #expect(document.placements[1].topY > last.baselineY)
    }
}
