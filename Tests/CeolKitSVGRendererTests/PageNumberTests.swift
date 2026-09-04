//
//  PageNumberTests.swift
//  CeolKitSVGRendererTests
//
//  %%ceolkit:pagenumber reaching the page it numbers — issue #138.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

private func parse(_ source: String) -> ParseResult {
    CeolKitParser().parse(source, options: .default)
}

/// One short tune, whose footer prints whatever the placeholders resolve to.
private func oneTune(_ preamble: String, footer: String = "P=$P") -> String {
    """
    \(preamble)
    %%footer "\(footer)"
    X:1
    T:A
    M:4/4
    L:1/8
    K:G
    GABG|DEFD|
    """
}

/// Enough music to fill several pages of a page size deliberately made short.
private func longTune(_ preamble: String) -> String {
    let body = Array(repeating: "GABG|DEFD|GABG|D4|", count: 40).joined(separator: "\n")
    return """
    \(preamble)
    %%footer "P=$P"
    X:1
    T:A
    M:4/4
    L:1/8
    K:G
    \(body)
    """
}

private func footers(of abc: String, pageSize: PageSize = .letter) throws -> [String] {
    var config = SVGRenderConfig()
    config.pageSize = pageSize
    config.textRendering = .fontFace
    return try SVGRenderer(config: config).render(parse(abc).score).map { page in
        page.firstMatch(of: #/class="footer">([^<]*)</#).map { String($0.1) } ?? ""
    }
}

@Suite("%%ceolkit:pagenumber (#138)")
struct PageNumberTests {

    @Test func theFirstPagePrintsTheNumberTheDirectiveAsksFor() throws {
        #expect(try footers(of: oneTune("%%ceolkit:pagenumber 3")) == ["P=3"])
    }

    @Test func withoutTheDirectivePagesStillNumberFromOne() throws {
        #expect(try footers(of: oneTune("%%dateformat \"%Y\"")) == ["P=1"])
    }

    @Test func laterPagesCarryOnFromTheStatedNumber() throws {
        // A short page forces several of them, so the sequence — not just the first page —
        // is what gets checked.
        let printed = try footers(of: longTune("%%ceolkit:pagenumber 17"),
                                  pageSize: PageSize(width: 612, height: 300))
        try #require(printed.count > 2, "the fixture must span several pages to be worth testing")
        #expect(printed == (0..<printed.count).map { "P=\(17 + $0)" })
    }

    @Test func theDirectiveWorksInTheFirstTunesHeaderToo() throws {
        let abc = """
        %%footer "P=$P"
        X:1
        T:A
        %%ceolkit:pagenumber 5
        M:4/4
        L:1/8
        K:G
        GABG|
        """
        #expect(try footers(of: abc) == ["P=5"])
    }

    @Test func theLastStatementOfTheNumberWins() throws {
        #expect(try footers(of: oneTune("%%ceolkit:pagenumber 3\n%%ceolkit:pagenumber 8"))
                == ["P=8"])
    }

    @Test func aCopyInALaterTunesHeaderIsIgnored() throws {
        // The directive sets the number *before any output has been produced*.  A second
        // tune's header is past that point, and renumbering pages already engraved is
        // %%newpage's job, not this directive's.
        let abc = """
        %%footer "P=$P"
        X:1
        T:A
        M:4/4
        L:1/8
        K:G
        GABG|

        X:2
        T:B
        %%ceolkit:pagenumber 9
        M:4/4
        L:1/8
        K:G
        GABG|
        """
        #expect(try footers(of: abc).first == "P=1")
    }

    @Test func theScrollSyncMetadataAgreesWithTheFooter() throws {
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let pages = try SVGRenderer(config: config)
            .render(parse(oneTune("%%ceolkit:pagenumber 3")).score)
        #expect(pages[0].contains("\"page\": 3"))
    }

    @Test func aSubstitutionMarkInheritsTheSameNumber() throws {
        // ${pagenumber} is documented as "the same value as $P" (#137), so the offset has to
        // reach it too — a binder compiler reading the default has to see what was drawn.
        let printed = try footers(of: oneTune("%%ceolkit:pagenumber 4",
                                              footer: "${pagenumber}"))
        #expect(printed == ["4"])
    }
}
