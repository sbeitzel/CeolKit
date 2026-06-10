import Foundation
import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Shared fixture

private let kalabakan = """
    %abc-2.2
    %%ceolkit:pipeformat true
    %%titleformat T0, R-1 C1
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

    @Test("SVG contains the rhythm field text")
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
        let score = parseScore(kalabakan)
        let metadata = try BravuraMetadata.load()
        let config = SVGRenderConfig()
        let effectiveConfig: SVGRenderConfig = {
            var c = config
            for scope in score.tunes.first?.directives ?? [] {
                if case .landscape(let on) = scope.directive {
                    c.pageSize = on ? config.pageSize.landscape : config.pageSize
                }
            }
            return c
        }()

        let sizer     = MeasureSizer(config: effectiveConfig, metadata: metadata)
        let breaker   = LineBreaker()
        let justifier = Justifier()
        let engine    = VerticalLayoutEngine(config: effectiveConfig, metadata: metadata)
        let usableWidth = effectiveConfig.pageSize.width - effectiveConfig.margins.left - effectiveConfig.margins.right

        guard let tune = score.tunes.first, let voice = tune.voices.first else {
            Issue.record("No tune/voice"); return
        }
        var pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] = []
        for stave in voice.staves {
            for m in stave.measures {
                pairs.append((sizer.size(m, unitNoteLength: tune.unitNoteLength), nil))
            }
        }
        let firstHeaderW = systemHeaderWidth(
            clef: voice.properties.clef, keySignature: tune.key, meter: tune.meter,
            metadata: metadata, staffSize: effectiveConfig.staffSize)
        let laterHeaderW = systemHeaderWidth(
            clef: voice.properties.clef, keySignature: tune.key, meter: nil,
            metadata: metadata, staffSize: effectiveConfig.staffSize)
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                               firstSystemHeaderWidth: firstHeaderW,
                                               laterSystemHeaderWidth: laterHeaderW,
                                               clef: voice.properties.clef,
                                               keySignature: tune.key,
                                               meter: tune.meter)
        let headerWidths = systems.enumerated().map { i, _ in i == 0 ? firstHeaderW : laterHeaderW }
        let justified = justifier.justify(systems, usableWidth: usableWidth,
                                          justifyLastSystem: false,
                                          systemHeaderWidths: headerWidths)

        var formatString: String? = nil
        for scope in tune.directives {
            if case .titleFormat(let fmt) = scope.directive { formatString = fmt; break }
        }
        guard let fmt = formatString else { Issue.record("No titleFormat directive"); return }

        let spec = TitleFormatParser.parse(fmt)
        let resolved = TitleResolver(tune: tune).resolve(spec)
        let lineHeight = effectiveConfig.staffSize * 2.5
        let titleBlockHeight = lineHeight * Double(resolved.count) + effectiveConfig.staffSize

        let layout = engine.layout(justified, titleRows: [], titleBlockHeight: titleBlockHeight)

        guard let firstSystem = layout.pages.first?.systems.first else {
            Issue.record("No systems in layout"); return
        }
        let staffTopY = firstSystem.origin.y + firstSystem.staffOrigin
        let titleEndY = effectiveConfig.margins.top + titleBlockHeight
        #expect(staffTopY >= titleEndY,
                "Expected staff top (\(staffTopY)) ≥ title block bottom (\(titleEndY))")
    }

    // MARK: - Empty / absent titleformat

    @Test("Empty %%titleformat produces no title text in SVG")
    func emptyTitleFormatNoRows() throws {
        let abc = "%%titleformat \nX:1\nT:Test\nM:4/4\nL:1/4\nK:C\nCDEF|"
        let pages = try SVGRenderer().render(parseScore(abc))
        let svg = try #require(pages.first)
        #expect(!svg.contains(">Test<"))
    }

    @Test("Tune with no %%titleformat directive has no title block text")
    func noDirectiveNoTitleBlock() throws {
        let abc = "X:1\nT:My Tune\nM:4/4\nL:1/4\nK:C\nCDEF|"
        let pages = try SVGRenderer().render(parseScore(abc))
        let svg = try #require(pages.first)
        #expect(!svg.contains(">My Tune<"))
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
