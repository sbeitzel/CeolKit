//
//  FooterScopeTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #155: `%%footer` and `%%dateformat` are scoped like every other stylesheet
//  directive — one in the file header governs the document, one in a tune header governs
//  that tune (ABC v2.2 §4.23) — and a page prints the footer of the tune that opens it.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("Footer scope across tunes (#155)")
struct FooterScopeTests {

    // MARK: - Sources

    /// `count` tunes of identical music, with `headers[i]` inserted into tune *i*'s header.
    private func tunes(_ headers: [String?], body: String = "CDEF|") -> String {
        headers.enumerated().map { index, header in
            (["X:\(index + 1)", "T:Tune \(index + 1)", "M:4/4", "L:1/4", header, "K:C", body]
                as [String?])
                .compactMap { $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Probes

    private func layout(_ abc: String) throws -> ResolvedLayout {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score).layout
    }

    /// The footer text each page prints, in page order.  A page with no footer reads `""`.
    private func footers(of abc: String) throws -> [String] {
        try layout(abc).pages.map { page in
            page.footerRows.flatMap(\.items).map(\.text).joined()
        }
    }

    // MARK: - Per-tune footers

    @Test("Each tune's pages print that tune's own header footer")
    func eachTunePrintsItsOwnFooter() throws {
        // A `%%newpage` in each tune after the first keeps the tunes off one another's
        // pages, so page-to-tune is one-to-one and the footers are unambiguous.
        let abc = tunes([#"%%footer "First tune""#,
                         "%%footer \"Second tune\"\n%%newpage",
                         "%%footer \"Third tune\"\n%%newpage"])
        #expect(try footers(of: abc) == ["First tune", "Second tune", "Third tune"])
    }

    @Test("A file-header %%footer prints on every page")
    func fileHeaderFooterPrintsEverywhere() throws {
        let abc = #"%%footer "Whole book""# + "\n"
            + tunes([nil, "%%newpage", "%%newpage"])
        #expect(try footers(of: abc) == ["Whole book", "Whole book", "Whole book"])
    }

    @Test("A tune header footer overrides the file header's for that tune alone")
    func tuneHeaderOverridesFileHeaderForOneTuneOnly() throws {
        let abc = #"%%footer "Book""# + "\n"
            + tunes([nil, "%%footer \"Tune two\"\n%%newpage", "%%newpage"])
        #expect(try footers(of: abc) == ["Book", "Tune two", "Book"])
    }

    @Test(#"%%footer "" in a tune header leaves that tune's pages bare"#)
    func emptyTuneFooterSuppressesTheBookFooter() throws {
        let abc = #"%%footer "Book""# + "\n"
            + tunes([nil, "%%footer \"\"\n%%newpage", "%%newpage"])
        #expect(try footers(of: abc) == ["Book", "", "Book"])
    }

    // MARK: - Pages two tunes share

    @Test("A page two tunes share prints the footer of the tune that opens it")
    func sharedPageTakesTheOpeningTunesFooter() throws {
        // Two short tunes, nothing forcing them apart: they land on one page together.
        let abc = tunes([#"%%footer "First tune""#, #"%%footer "Second tune""#])
        let pages = try layout(abc).pages
        #expect(pages.count == 1)
        #expect(pages[0].openingTuneIndex == 0)
        #expect(try footers(of: abc) == ["First tune"])
    }

    @Test("A tune spilling onto a page still owns it, even where the next tune starts there")
    func spilloverTuneOwnsThePageItContinuesOnto() throws {
        // Tune 1 is long enough to run past one page; tune 2 follows it onto the page its
        // tail lands on.  The page opens with tune 1's music, so it is tune 1's page.
        let long = String(repeating: "CDEF|\n", count: 60)
        let abc = tunes([#"%%footer "First tune""#, #"%%footer "Second tune""#], body: long)
        let pages = try layout(abc).pages
        #expect(pages.count > 1)
        #expect(pages[0].openingTuneIndex == 0)
        #expect(pages[1].openingTuneIndex == 0)
        let texts = try footers(of: abc)
        #expect(texts[0] == "First tune")
        #expect(texts[1] == "First tune")
        #expect(texts.last == "Second tune")
    }

    // MARK: - $T follows the same tune

    @Test("$T names the tune whose page it is, not the first tune in the document")
    func titlePlaceholderFollowsThePagesTune() throws {
        let abc = #"%%footer "$T""# + "\n" + tunes([nil, "%%newpage", "%%newpage"])
        #expect(try footers(of: abc) == ["Tune 1", "Tune 2", "Tune 3"])
    }

    // MARK: - %%dateformat

    @Test("%%dateformat in a tune header dates that tune's pages and no others")
    func dateFormatIsScopedToItsTune() throws {
        // `\%` rather than `%`, which would start an ABC comment; the renderer unescapes it
        // before handing the pattern to `strftime`.
        let abc = #"%%footer "$D""# + "\n"
            + #"%%dateformat \%Y"# + "\n"
            + tunes([nil, #"%%dateformat in the year of our tune"# + "\n%%newpage", "%%newpage"])
        let texts = try footers(of: abc)
        #expect(texts.count == 3)
        #expect(texts[1] == "in the year of our tune")
        // The tunes either side keep the file header's format — a four-digit year.
        #expect(texts[0] == texts[2])
        #expect(texts[0].count == 4 && texts[0].allSatisfy(\.isNumber))
    }
}
