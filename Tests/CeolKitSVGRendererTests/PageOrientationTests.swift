//
//  PageOrientationTests.swift
//  CeolKitSVGRendererTests
//
//  %%landscape reaching the page it turns — issue #158.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

private func parse(_ source: String) -> ParseResult {
    CeolKitParser().parse(source, options: .default)
}

private func render(_ abc: String) throws -> [String] {
    var config = SVGRenderConfig()
    config.textRendering = .fontFace
    return try SVGRenderer(config: config).render(parse(abc).score)
}

/// The width and height each emitted page declares, read back out of the document the way
/// `CeolKitSVGGeometry` does — from the `<svg>` element itself, one page at a time.
private func pageSizes(of abc: String) throws -> [Size] {
    try render(abc).map { page in
        guard let match = page.firstMatch(of: #/width="([\d.]+)pt" height="([\d.]+)pt"/#)
        else { return .zero }
        return Size(width: Double(match.1) ?? 0, height: Double(match.2) ?? 0)
    }
}

/// US Letter, the renderer default, in both orientations.
private let portrait  = Size(width: 612, height: 792)
private let landscape = Size(width: 792, height: 612)

private func diagnostics(_ abc: String, code: DiagnosticCode) -> [Diagnostic] {
    parse(abc).score.diagnostics.filter { $0.code == code }
}

@Suite("%%landscape and page orientation (#158)")
struct PageOrientationTests {

    /// Two short tunes that would otherwise sit on one page together, with whatever is
    /// handed in standing in the gap between them.
    private func twoTunes(_ between: String) -> String {
        """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|

        \(between)
        X:2
        T:Second
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|
        """
    }

    // MARK: - The issue's own example

    @Test("A %%landscape at a %%newpage turns that page and leaves the one before it alone")
    func orientationChangesAtABreak() throws {
        let sizes = try pageSizes(of: """
        %%landscape 1
        \(twoTunes("%%newpage\n%%landscape 0"))
        """)
        #expect(sizes == [landscape, portrait])
    }

    @Test("The reverse: a portrait document turns landscape at a break")
    func portraitTurnsLandscape() throws {
        let sizes = try pageSizes(of: twoTunes("%%newpage\n%%landscape 1"))
        #expect(sizes == [portrait, landscape])
    }

    @Test("The %%landscape may be written before the %%newpage it takes effect at")
    func orderWithinTheGapDoesNotMatter() throws {
        let sizes = try pageSizes(of: """
        %%landscape 1
        \(twoTunes("%%landscape 0\n%%newpage"))
        """)
        #expect(sizes == [landscape, portrait])
    }

    // MARK: - Regression: the file header still governs the document

    @Test("%%landscape in the file header turns every page")
    func fileHeaderGovernsTheDocument() throws {
        let sizes = try pageSizes(of: """
        %%landscape 1
        \(twoTunes("%%newpage"))
        """)
        #expect(sizes == [landscape, landscape])
    }

    @Test("A document that says nothing is portrait throughout")
    func defaultIsPortrait() throws {
        let sizes = try pageSizes(of: twoTunes("%%newpage"))
        #expect(sizes == [portrait, portrait])
    }

    // MARK: - No break to take effect at

    @Test("%%landscape in the gap with no %%newpage is diagnosed and ignored")
    func gapWithoutABreakIsIgnored() throws {
        let abc = """
        %%landscape 1
        \(twoTunes("%%landscape 0"))
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).count == 1)
        // The two tunes share the one page they always did, and it is still landscape.
        let sizes = try pageSizes(of: abc)
        #expect(sizes == [landscape])
    }

    @Test("%%landscape in a tune header with no %%newpage is diagnosed and ignored")
    func tuneHeaderWithoutABreakIsIgnored() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|

        X:2
        %%landscape 1
        T:Second
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).count == 1)
        #expect(try pageSizes(of: abc) == [portrait])
    }

    @Test("A bare mid-tune %%landscape is diagnosed and ignored")
    func bareMidTuneIsIgnored() throws {
        let abc = """
        X:1
        T:Only
        M:4/4
        L:1/4
        K:C
        CDEF|
        %%landscape 1
        GABc|
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).count == 1)
        #expect(try pageSizes(of: abc) == [portrait])
    }

    @Test("%%landscape past the last tune has no page left to turn")
    func afterTheLastTuneIsIgnored() throws {
        let abc = twoTunes("") + "\n%%landscape 1\n"
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).count == 1)
        #expect(try pageSizes(of: abc) == [portrait])
    }

    // MARK: - A tune header break

    @Test("%%landscape and %%newpage in a tune header turn that tune's pages")
    func tuneHeaderBreakIsHonoured() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|

        X:2
        %%newpage
        %%landscape 1
        T:Second
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).isEmpty)
        #expect(try pageSizes(of: abc) == [portrait, landscape])
    }

    @Test("A tune header's %%landscape beats one in the gap above it")
    func headerBeatsGap() throws {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:C
        CDEF|

        %%newpage
        %%landscape 1
        X:2
        %%landscape 0
        T:Second
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).isEmpty)
        #expect(try pageSizes(of: abc) == [portrait, portrait])
    }

    // MARK: - Mid-tune

    @Test("%%landscape at a mid-tune %%newpage turns the pages from there on")
    func midTuneBreakIsHonoured() throws {
        let abc = """
        X:1
        T:Only
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|
        %%newpage
        %%landscape 1
        CDEF|GABc|
        CDEF|GABc|
        """
        #expect(diagnostics(abc, code: .landscapeWithoutPageBreak).isEmpty)
        #expect(try pageSizes(of: abc) == [portrait, landscape])
    }

    @Test("The systems after a mid-tune turn are broken to the new page's width")
    func midTuneSystemsFillTheNewWidth() throws {
        // `%%ceolkit:justifylast` so that both systems are stretched to their own page's
        // line: without it the last system of the tune is left at its natural width, which
        // is the same music either side of the break and so says nothing about the width it
        // was given.
        let abc = """
        %%ceolkit:justifylast true
        X:1
        T:Only
        M:4/4
        L:1/4
        K:C
        CDEF|GABc|
        %%newpage
        %%landscape 1
        CDEF|GABc|
        """
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let document = try SVGRenderer(config: config).renderDocument(parse(abc).score)
        #expect(document.layout.pages.count == 2)
        let portraitSystem  = try #require(document.layout.pages.first?.systems.first)
        let landscapeSystem = try #require(document.layout.pages.last?.systems.first)
        // Same music, justified to a line 180pt wider (792 - 612): the landscape system's
        // closing bar line lands exactly that much further right.
        let portraitLast  = try #require(portraitSystem.measures.last)
        let landscapeLast = try #require(landscapeSystem.measures.last)
        let portraitRight  = portraitLast.origin.x + portraitLast.width
        let landscapeRight = landscapeLast.origin.x + landscapeLast.width
        #expect(landscapeRight - portraitRight == 180)
    }

    // MARK: - Pagination

    @Test("Orientation changes how much music a page holds")
    func paginationFollowsTheOrientation() throws {
        // Eleven staves of one bar each: more than a portrait page holds, and the landscape
        // page that follows is shorter still, so the page counts differ between the two.
        let staves = Array(repeating: "CDEF|", count: 11).joined(separator: "\n")
        let head = """
        X:1
        T:Only
        M:4/4
        L:1/4
        K:C

        """
        let portraitPages  = try render(head + staves).count
        let landscapePages = try render("%%landscape 1\n" + head + staves).count
        #expect(portraitPages == 1)
        #expect(landscapePages > portraitPages)
    }

    // MARK: - Numbering and orientation on one break

    @Test("%%newpage N and %%landscape at one break are both honoured")
    func numberingAndOrientationTogether() throws {
        let abc = twoTunes("%%newpage 20\n%%landscape 1")
        #expect(try pageSizes(of: abc) == [portrait, landscape])
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let document = try SVGRenderer(config: config).renderDocument(parse(abc).score)
        #expect(document.layout.pages.map(\.pageNumber) == [1, 20])
        #expect(document.layout.pages.map(\.pageSize) == [
            Size(width: 612, height: 792), Size(width: 792, height: 612)
        ])
    }

    // MARK: - The document default

    @Test("ResolvedLayout.pageSize stays the document default a hand-built layout relies on")
    func layoutKeepsTheDocumentDefault() throws {
        let abc = """
        %%landscape 1
        \(twoTunes("%%newpage\n%%landscape 0"))
        """
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let document = try SVGRenderer(config: config).renderDocument(parse(abc).score)
        #expect(document.layout.pageSize == Size(width: 792, height: 612))
    }
}
