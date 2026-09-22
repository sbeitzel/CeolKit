//
//  FooterLabelTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #168: `%%ceolkit:label` supplies the value a `${label}` footer mark draws, scoped
//  the way `%%footer` is — the file header's covers the document, a tune header's covers
//  that tune.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("Footer label directive (#168)")
struct FooterLabelTests {

    /// `headers.count` tunes of identical music, with `headers[i]` inserted into tune *i*'s
    /// header and every tune after the first starting a fresh page.
    private func tunes(_ headers: [String?]) -> String {
        headers.enumerated().map { index, header in
            (["X:\(index + 1)", "T:Tune \(index + 1)", "M:4/4", "L:1/4", header,
              index == 0 ? nil : "%%newpage", "K:C", "CDEF|"] as [String?])
                .compactMap { $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    private func layout(_ abc: String) throws -> ResolvedLayout {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score).layout
    }

    /// What each page's `${label}` mark draws, in page order; `nil` for a page with none.
    private func labels(of abc: String) throws -> [String?] {
        try layout(abc).pages.map { page in
            page.footerRows.flatMap(\.items).first { $0.tag == "label" }?.text
        }
    }

    @Test("Each tune's pages print that tune's own label")
    func eachTunePrintsItsOwnLabel() throws {
        let abc = #"%%footer "${label}""# + "\n"
            + tunes([#"%%ceolkit:label "Jigs""#, #"%%ceolkit:label "Reels""#])
        #expect(try labels(of: abc) == ["Jigs", "Reels"])
    }

    @Test("A file-header label covers every tune that does not set its own")
    func fileHeaderLabelCoversTheDocument() throws {
        let abc = "%%footer \"${label}\"\n%%ceolkit:label \"Book\"\n"
            + tunes([nil, #"%%ceolkit:label "Tune two""#, nil])
        #expect(try labels(of: abc) == ["Book", "Tune two", "Book"])
    }

    @Test(#"%%ceolkit:label "" in a tune header clears the file header's for that tune"#)
    func emptyTuneLabelClearsTheFileLabel() throws {
        let abc = "%%footer \"${label}\"\n%%ceolkit:label \"Book\"\n"
            + tunes([nil, #"%%ceolkit:label """#])
        #expect(try labels(of: abc) == ["Book", ""])
    }

    @Test("${label} with no directive still produces the positioned empty group")
    func labelWithoutDirectiveIsAnEmptyGroup() throws {
        let abc = #"%%footer "${pagenumber}\t${label}\t$D""# + "\n" + tunes([nil])
        #expect(try labels(of: abc) == [""])
        let svg = try SVGRenderer().render(CeolKitParser().parse(abc, options: .default).score)
            .joined()
        #expect(svg.contains(#"data-ceolkit-tag="label""#))
    }

    @Test("A label containing $P or ${pagenumber} is printed exactly as written")
    func labelIsNotExpanded() throws {
        let abc = "%%footer \"${label}\"\n%%ceolkit:label \"Page $P of ${pagenumber}\"\n"
            + tunes([nil])
        #expect(try labels(of: abc) == ["Page $P of ${pagenumber}"])
    }
}
