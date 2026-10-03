//
//  FooterBandTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #192: layout keeps music out of the strip a `%%footer` is printed in.  Footers are
//  stamped on after layout, so the engine used to test fit against the bare bottom margin and
//  a page's last system could print through its footer.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("Footer band reserved in layout (#192)")
struct FooterBandTests {

    // MARK: - Sources

    private let line = "|: A2 B2 c2 d2 | e2 f2 g2 a2 | a2 g2 f2 e2 | d2 c2 B2 A2 :|"

    /// The issue's reproduction: one tune of `lines` identical lines.
    private func longTune(lines: Int, preamble: String) -> String {
        preamble + """
            %%ceolkit:scale 0.88
            X:1
            T:Footer collision
            M:4/4
            L:1/8
            K:D

            """ + Array(repeating: line, count: lines).joined(separator: "\n") + "\n"
    }

    /// A tune of `lines` lines followed by a one-line tune, which may share its page.
    private func twoTunes(lines: Int, scale: Double, preamble: String) -> String {
        preamble + """
            %%ceolkit:scale \(scale)
            X:1
            T:Long
            M:4/4
            L:1/8
            K:D

            """ + Array(repeating: line, count: lines).joined(separator: "\n") + """


            X:2
            T:Short
            M:4/4
            L:1/8
            K:D
            \(line)

            """
    }

    private let footer = #"%%footer "\tPage $P\t""# + "\n"

    // MARK: - Probes

    private func render(_ abc: String) throws -> RenderedDocument {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score)
    }

    /// Whether the second tune starts part-way down a page, below the first, rather than at
    /// the top of a page of its own.
    private func sharesAPage(_ document: RenderedDocument) -> Bool {
        document.placements[1].topY > document.layout.margins.top
    }

    /// Fails for every page whose lowest system reaches into the top of its footer's text.
    private func expectMusicClearsFooter(_ layout: ResolvedLayout,
                                         sourceLocation: SourceLocation = #_sourceLocation) {
        for (index, page) in layout.pages.enumerated() {
            guard let footerBaseline = page.footerRows.first?.items.first?.baselineY,
                  let lowest = page.systems.map({ $0.origin.y + $0.totalHeight }).max()
            else { continue }
            let footerTop = footerBaseline
                - FooterBand.fontSize * LibertinusSerifMetrics.ascenderRatio
            #expect(lowest <= footerTop,
                    "page \(index): music reaches \(lowest), footer starts at \(footerTop)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: - Tests

    @Test("The issue's reproduction: no system prints over the footer")
    func reproductionClearsTheFooter() throws {
        let layout = try render(longTune(lines: 30, preamble: footer)).layout
        #expect(layout.pages.allSatisfy { !$0.footerRows.isEmpty })
        expectMusicClearsFooter(layout)
    }

    @Test("Music clears the footer whatever the tune's length", arguments: 1...40)
    func musicClearsTheFooterAtEveryLength(lines: Int) throws {
        expectMusicClearsFooter(try render(longTune(lines: lines, preamble: footer)).layout)
    }

    @Test("A tune that fits above the margin but not above the footer opens a new page")
    func tuneThatOnlyFitsWithoutAFooterMovesOn() throws {
        // Somewhere in this sweep the short second tune fits above the bare bottom margin but
        // not above the footer band.  No one length and scale is pinned, so changes to
        // vertical spacing elsewhere cannot quietly make this test vacuous.
        var sawTheBoundary = false
        for lines in [16, 20, 24] {
            for scale in stride(from: 0.80, through: 1.0, by: 0.02) {
                let bare = try render(twoTunes(lines: lines, scale: scale, preamble: ""))
                let footed = try render(twoTunes(lines: lines, scale: scale, preamble: footer))
                expectMusicClearsFooter(footed.layout)
                if sharesAPage(bare) && !sharesAPage(footed) { sawTheBoundary = true }
            }
        }
        #expect(sawTheBoundary)
    }

    @Test("A document with no footer reserves nothing")
    func noFooterLeavesLayoutUnchanged() throws {
        // A page filled to within the footer band of its margin with no footer to dodge:
        // the issue's own reproduction put a system there, and without `%%footer` it stays.
        let bare = try render(longTune(lines: 30, preamble: "")).layout
        let floor = bare.pageSize.height - bare.margins.bottom
        let lowest = bare.pages[0].systems.map { $0.origin.y + $0.totalHeight }.max() ?? 0
        #expect(lowest > floor - FooterBand.reservedHeight)
        #expect(lowest <= floor)
    }

    @Test(#"An empty %%footer reserves nothing"#)
    func emptyFooterReservesNothing() throws {
        let bare = try render(longTune(lines: 30, preamble: "")).layout
        let empty = try render(longTune(lines: 30, preamble: #"%%footer """# + "\n")).layout
        #expect(bare.pages.map(\.systems.count) == empty.pages.map(\.systems.count))
        #expect(bare.pages.map { $0.systems.map(\.origin.y) }
                == empty.pages.map { $0.systems.map(\.origin.y) })
    }
}
