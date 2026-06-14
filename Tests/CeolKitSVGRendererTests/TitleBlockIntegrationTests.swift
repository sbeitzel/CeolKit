import Foundation
import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Shared fixture

private let kalabakan = """
    %abc-2.2
    %%ceolkit:pipeformat true
    %%writefields R
    %%flatbeams true
    %%landscape 1
    X:1
    T:Kalabakan (Borneo)
    R:Reel
    C:P/M A. MacDonald
    M:C|
    L:1/8
    K:D
    AB cd|
    """

private func parseScore(_ abc: String) -> Score {
    CeolKitParser().parse(abc, options: .default).score
}

@Suite("Title block integration")
struct TitleBlockIntegrationTests {

    // MARK: - Content presence

    @Test("SVG contains the tune title text")
    func titlePresentInSVG() throws {
        let pages = try SVGRenderer().render(parseScore(kalabakan))
        let firstPage = try #require(pages.first)
        #expect(firstPage.contains("Kalabakan (Borneo)"))
    }

    @Test("SVG contains the rhythm field text when %%writefields R is set")
    func rhythmPresentInSVG() throws {
        let pages = try SVGRenderer().render(parseScore(kalabakan))
        let firstPage = try #require(pages.first)
        #expect(firstPage.contains("Reel"))
    }

    @Test("SVG contains the composer field text")
    func composerPresentInSVG() throws {
        let pages = try SVGRenderer().render(parseScore(kalabakan))
        let firstPage = try #require(pages.first)
        #expect(firstPage.contains("P/M A. MacDonald"))
    }

    // MARK: - Layout

    @Test("Title baseline Y is less than the first system's staff Y (title is above staff)")
    func titleAboveStaff() throws {
        let pages = try SVGRenderer().render(parseScore(kalabakan))
        let svg = try #require(pages.first)

        let titleYValues: [Double] = svg
            .components(separatedBy: "<text ")
            .dropFirst()
            .filter { $0.contains("Libertinus Serif") && !$0.contains("class=\"footer\"") }
            .compactMap { segment -> Double? in
                guard let yStart = segment.range(of: " y=\"") else { return nil }
                let afterY = segment[yStart.upperBound...]
                guard let yEnd = afterY.firstIndex(of: "\"") else { return nil }
                return Double(afterY[afterY.startIndex..<yEnd])
            }

        let lineMinY: Double = svg
            .components(separatedBy: "<line ")
            .dropFirst()
            .flatMap { segment -> [Double] in
                var vals: [Double] = []
                for attr in ["y1=\"", "y2=\""] {
                    if let s = segment.range(of: attr) {
                        let after = segment[s.upperBound...]
                        if let e = after.firstIndex(of: "\""),
                           let v = Double(after[after.startIndex..<e]) {
                            vals.append(v)
                        }
                    }
                }
                return vals
            }
            .min() ?? .infinity

        guard !titleYValues.isEmpty else { Issue.record("No Libertinus Serif text found in SVG"); return }
        guard lineMinY < .infinity   else { Issue.record("No <line> elements found in SVG"); return }

        let titleMaxY = titleYValues.max()!
        #expect(titleMaxY < lineMinY,
                "Title baseline (\(titleMaxY)) must be strictly above topmost music line (\(lineMinY))")
    }

    // MARK: - Default field set

    @Test("Title appears in SVG by default with no %%writefields directive")
    func defaultShowsTitle() throws {
        let abc = "X:1\nT:My Tune\nM:4/4\nL:1/4\nK:C\nCDEF|"
        let pages = try SVGRenderer().render(parseScore(abc))
        let svg = try #require(pages.first)
        #expect(svg.contains("My Tune"))
    }

    @Test("%%writefields T false suppresses title in SVG")
    func writeFieldsTFalseSuppressesTitle() throws {
        let abc = "%%writefields T false\nX:1\nT:Test\nM:4/4\nL:1/4\nK:C\nCDEF|"
        let pages = try SVGRenderer().render(parseScore(abc))
        let svg = try #require(pages.first)
        #expect(!svg.contains(">Test<"))
    }

    // MARK: - Multi-page: title only on first page

    @Test("Second page has no title rows when layout spans multiple pages")
    func secondPageNoTitleRows() throws {
        let metadata = try BravuraMetadata.load()
        let config = SVGRenderConfig()
        let engine = VerticalLayoutEngine(config: config, metadata: metadata)

        let titleRow = ResolvedTitleRow(items: [
            ResolvedTitleRow.Item(
                text: "Test Title", x: 100, baselineY: 20,
                anchor: .middle, fontSize: 14)
        ])

        // Build enough justified systems to fill more than one page by repeating a dummy.
        let dummyMeasure = SizedMeasure(
            measure: Measure(
                openingBar: nil,
                events: [],
                closingBar: BarLine(
                    kind: .single,
                    source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
                ),
                endingNumber: nil,
                source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
            ),
            naturalWidth: 50,
            eventOffsets: []
        )
        let jm = JustifiedMeasure(source: dummyMeasure, finalWidth: 50, eventOffsets: [])
        let systemHeight = 4.0 * config.staffSize + config.systemGap
        let systemsNeeded = Int(ceil(config.pageSize.height / systemHeight)) + 2
        let systems: [JustifiedSystem] = (0..<systemsNeeded).map { i in
            JustifiedSystem(
                measures: [jm],
                isLastSystem: i == systemsNeeded - 1,
                sourceForced: false
            )
        }

        let layout = engine.layout(systems, titleRows: [titleRow], titleBlockHeight: 40)

        if layout.pages.count >= 2 {
            #expect(layout.pages[1].titleRows.isEmpty)
        }
        #expect(!layout.pages[0].titleRows.isEmpty)
    }
}
