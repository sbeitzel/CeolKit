//
//  NewPageTests.swift
//  CeolKitSVGRendererTests
//
//  %%newpage reaching the page it breaks — issue #140.
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

/// What each page's footer prints, which is where `$P` lands.
private func footers(of abc: String) throws -> [String] {
    try render(abc).map { page in
        page.firstMatch(of: #/class="footer">([^<]*)</#).map { String($0.1) } ?? ""
    }
}

/// The systems on each page, named by the source line each was engraved from.
///
/// Read back out of the `ceolkit-meta` scroll-sync comment, which carries one anchor per
/// system: it is the only per-system marker in the document that survives outlining, and it
/// says *which* music landed on the page as well as how much.
private func systemLines(of abc: String) throws -> [[Int]] {
    try render(abc).map { page in
        page.matches(of: #/"abcLine": (\d+)/#).compactMap { Int($0.1) }
    }
}

@Suite("%%newpage (#140)")
struct NewPageTests {

    /// Two short tunes that would otherwise sit on one page together.
    private func twoTunes(_ between: String) -> String {
        """
        X:1
        T:First
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        \(between)
        X:2
        T:Second
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """
    }

    // MARK: - Where the break falls

    @Test func withoutTheDirectiveTwoShortTunesShareAPage() throws {
        #expect(try render(twoTunes("")).count == 1)
    }

    @Test func aBreakBetweenTwoTunesPutsTheSecondOnItsOwnPage() throws {
        let pages = try render(twoTunes("\n%%newpage"))
        try #require(pages.count == 2)
        #expect(pages[0].contains(">First<"))
        #expect(pages[1].contains(">Second<"))
    }

    @Test func aBreakInATunesHeaderMovesThatTune() throws {
        let pages = try render("""
        X:1
        T:First
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|

        X:2
        %%newpage
        T:Second
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        """)
        try #require(pages.count == 2)
        #expect(pages[1].contains(">Second<"))
    }

    @Test func aBreakBelowTheLastStaveOfATuneMovesWhateverFollows() throws {
        // Written at the foot of tune 1's body rather than in the gap below it.  There is
        // nothing of tune 1 left to move, so what it moves is tune 2.
        let pages = try render(twoTunes("%%newpage"))
        try #require(pages.count == 2)
        #expect(pages[1].contains(">Second<"))
    }

    @Test func aBreakInTheBodySplitsTheTuneWhereItIsWritten() throws {
        let pages = try systemLines(of: """
        X:1
        T:Split
        M:4/4
        L:1/8
        K:G
        GABG|DEFD|
        %%newpage
        GABG|DEFD|
        GABG|DEFD|
        """)
        try #require(pages.count == 2)
        // The stave above the directive stays behind; the two below it move.
        #expect(pages[0] == [6])
        #expect(pages[1] == [8, 9])
    }

    @Test func aBreakAheadOfEveryTuneLeavesNoBlankPageBehindIt() throws {
        // Nothing has been engraved yet, so there is nothing to break away from.
        #expect(try render("%%newpage\n" + twoTunes("")).count == 1)
    }

    // MARK: - Page numbering

    @Test func aPlainBreakLeavesTheCountAlone() throws {
        #expect(try footers(of: "%%footer \"P=$P\"\n" + twoTunes("\n%%newpage"))
                == ["P=1", "P=2"])
    }

    @Test func newPageNRenumbersFromThere() throws {
        #expect(try footers(of: "%%footer \"P=$P\"\n" + twoTunes("\n%%newpage 20"))
                == ["P=1", "P=20"])
    }

    @Test func numberingCarriesOnFromTheRestartedNumber() throws {
        let printed = try footers(of: """
        %%footer "P=$P"
        X:1
        T:A
        M:4/4
        L:1/8
        K:G
        GABG|

        %%newpage 20
        X:2
        T:B
        M:4/4
        L:1/8
        K:G
        GABG|

        %%newpage
        X:3
        T:C
        M:4/4
        L:1/8
        K:G
        GABG|
        """)
        #expect(printed == ["P=1", "P=20", "P=21"])
    }

    @Test func aBreakAheadOfEveryTuneStillSetsTheOpeningNumber() throws {
        // No page to break, but `%%newpage 7` still says what the first one is called —
        // which is where it meets %%ceolkit:pagenumber written in the same place (#138).
        #expect(try footers(of: "%%newpage 7\n%%footer \"P=$P\"\n" + twoTunes(""))
                == ["P=7"])
    }

    @Test func theScrollSyncMetadataAgreesWithTheFooter() throws {
        let pages = try render("%%footer \"P=$P\"\n" + twoTunes("\n%%newpage 20"))
        try #require(pages.count == 2)
        #expect(pages[0].contains("\"page\": 1"))
        #expect(pages[1].contains("\"page\": 20"))
    }

    @Test func aBreakCarriesTheNumberEvenWhereTheNumberedTuneCameFirst() throws {
        // %%ceolkit:pagenumber sets the opening number and %%newpage moves on from it: the
        // two compose rather than competing (EXTENSIONS.md, "Interaction with %%newpage").
        #expect(try footers(of: "%%ceolkit:pagenumber 3\n%%footer \"P=$P\"\n"
                                + twoTunes("\n%%newpage"))
                == ["P=3", "P=4"])
    }

    // MARK: - Resolving staves to systems

    @Test func aBreakOnAStaveTheLayoutSplitLandsOnTheFirstOfItsSystems() throws {
        // The stave after the break is too wide for one line, so the packer makes several
        // systems out of it.  The break belongs in front of the first of them.
        let bars = Array(repeating: "GABG|", count: 12).joined()
        let pages = try systemLines(of: """
        X:1
        T:Wide
        M:4/4
        L:1/8
        K:G
        GABG|
        %%newpage
        \(bars)
        """)
        try #require(pages.count == 2)
        #expect(pages[0] == [6])
        #expect(pages[1].count > 1)
    }
}
