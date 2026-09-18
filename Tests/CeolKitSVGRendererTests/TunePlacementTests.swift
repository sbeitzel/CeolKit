//
//  TunePlacementTests.swift
//  CeolKitSVGRendererTests
//
//  Reading back where each tune landed — issue #152.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

private func parse(_ source: String) -> ParseResult {
    CeolKitParser().parse(source, options: .default)
}

/// One short tune per title given, in one document.
private func tunes(_ titles: [String], preamble: String = "") -> String {
    let bodies = titles.enumerated().map { index, title in
        """
        X:\(index + 1)
        T:\(title)
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """
    }
    return ([preamble] + bodies).filter { !$0.isEmpty }.joined(separator: "\n\n")
}

private func document(_ abc: String, pageSize: PageSize = .letter) throws -> RenderedDocument {
    var config = SVGRenderConfig()
    config.pageSize = pageSize
    return try SVGRenderer(config: config).renderDocument(parse(abc).score)
}

@Suite("Tune placements (#152)")
struct TunePlacementTests {

    @Test func everyTuneGetsOnePlacementInScoreOrder() throws {
        let doc = try document(tunes(["A", "B", "C"]))
        #expect(doc.placements.map(\.tuneIndex) == [0, 1, 2])
    }

    @Test func tunesThatSharePageStillReportDistinctTopY() throws {
        // Three short tunes fit on one letter page, which is exactly the case a consumer
        // cannot work out from the SVG: same page, different heights down it.
        let doc = try document(tunes(["A", "B", "C"]))
        try #require(doc.pages.count == 1)
        #expect(doc.placements.map(\.pageIndex) == [0, 0, 0])
        #expect(doc.placements[0].topY < doc.placements[1].topY)
        #expect(doc.placements[1].topY < doc.placements[2].topY)
    }

    @Test func theFirstTuneStartsAtTheTopMargin() throws {
        let doc = try document(tunes(["A"]))
        #expect(doc.placements[0].topY == SVGRenderConfig().margins.top)
    }

    @Test func aTuneSpilledOntoTheNextPageStartsAtTheTopMarginToo() throws {
        // A page short enough that the second tune cannot follow the first on it.
        let doc = try document(tunes(["A", "B"]), pageSize: PageSize(width: 612, height: 200))
        try #require(doc.pages.count == 2)
        #expect(doc.placements.map(\.pageIndex) == [0, 1])
        #expect(doc.placements[1].topY == SVGRenderConfig().margins.top)
    }

    @Test func aForcedPageBreakMovesTheTuneAndItsPlacement() throws {
        let abc = """
        X:1
        T:A
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|

        X:2
        T:B
        %%newpage
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """
        let doc = try document(abc)
        try #require(doc.pages.count == 2)
        #expect(doc.placements.map(\.pageIndex) == [0, 1])
    }

    @Test func printedPageNumbersFollowTheDirectivesNotTheIndex() throws {
        let abc = """
        %%ceolkit:pagenumber 17
        X:1
        T:A
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|

        X:2
        T:B
        %%newpage 40
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """
        let doc = try document(abc)
        #expect(doc.placements.map(\.pageIndex) == [0, 1])
        #expect(doc.placements.map(\.printedPageNumber) == [17, 40])
    }

    @Test func placementsAgreeWithThePageTheTitleWasDrawnOn() throws {
        // The cross-check that matters: the page the map names is the page whose title rows
        // hold that tune's title.
        let doc = try document(tunes(["Alpha", "Beta"]),
                               pageSize: PageSize(width: 612, height: 200))
        for (index, title) in ["Alpha", "Beta"].enumerated() {
            let placement = doc.placements[index]
            let page = doc.layout.pages[placement.pageIndex]
            let texts = page.titleRows.flatMap { $0.items.map(\.text) }
            #expect(texts.contains(title), "tune \(index) is not titled on page \(placement.pageIndex)")
        }
    }

    @Test func aPlacementNeverPointsPastTheLastPage() throws {
        let doc = try document(tunes(["A", "B", "C"]), pageSize: PageSize(width: 612, height: 200))
        #expect(doc.placements.allSatisfy { $0.pageIndex < doc.pages.count })
        #expect(doc.placements.map(\.pageIndex).sorted() == doc.placements.map(\.pageIndex))
    }

    @Test func renderDocumentEmitsWhatRenderEmits() throws {
        let score = parse(tunes(["A", "B"])).score
        let renderer = SVGRenderer()
        #expect(try renderer.renderDocument(score).pages == renderer.render(score))
    }

    @Test func theLayoutHandedBackIsTheOneWithFooters() throws {
        let doc = try document(tunes(["A"], preamble: "%%footer \"P=$P\""))
        #expect(doc.layout.pages.allSatisfy { !$0.footerRows.isEmpty })
    }

    @Test func aTuneWithNoMusicStillGetsAPlacement() throws {
        // Degenerate, but the map is documented as one entry per tune: a tune whose body is
        // empty must not shift the indices of the ones after it.
        let abc = """
        X:1
        T:A
        M:4/4
        L:1/8
        K:G

        X:2
        T:B
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """
        let doc = try document(abc)
        #expect(doc.placements.map(\.tuneIndex) == [0, 1])
        #expect(doc.placements.allSatisfy { $0.pageIndex < max(1, doc.pages.count) })
    }
}
