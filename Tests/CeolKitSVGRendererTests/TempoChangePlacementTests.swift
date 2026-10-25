import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #234: a tempo change is drawn above the staff, over the note after it, and takes
/// none of the staff's horizontal space — it used to be given a column six staff spaces
/// wide, which pushed the music after it to the right.
@Suite("A tempo change stands above the music without spacing it")
struct TempoChangePlacementTests {

    private func tune(_ body: String) -> String {
        ["X:1", "T:Tempo", "M:6/8", "L:1/8", "K:D", body].joined(separator: "\n") + "\n"
    }

    private func firstSystem(_ abc: String) throws -> ResolvedSystem {
        let score = CeolKitParser().parse(abc, options: .default).score
        let layout = try SVGRenderer().renderDocument(score).layout
        return try #require(layout.pages.first?.systems.first)
    }

    private func naturalWidths(_ abc: String) throws -> [Double] {
        let metadata = try BravuraMetadata.load()
        let sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
        let score = CeolKitParser().parse(abc, options: .default).score
        let voice = try #require(score.tunes.first?.voices.first)
        let bars = voice.staves.flatMap(\.measures)
        return bars.map { sizer.size($0).naturalWidth }
    }

    @Test("The issue's tune is spaced exactly as it is without its tempo changes")
    func tempoChangesTakeNoWidth() throws {
        let with = try naturalWidths(tune("Q:118\n|:a3 f2e|dfa [Q:1/4=88]b2a|"))
        let without = try naturalWidths(tune("|:a3 f2e|dfa b2a|"))
        #expect(with == without)
    }

    @Test("A tempo change stands over the note after it")
    func tempoChangeAlignsWithNextNote() throws {
        let system = try firstSystem(tune("a3 f2e|dfa [Q:1/4=88]b2a|]"))
        let events = system.measures.flatMap(\.events)
        let t = try #require(events.firstIndex {
            if case .tempoChange = $0.kind { return true }
            return false
        })
        let next = try #require(events[(t + 1)...].first {
            if case .note = $0.kind { return true }
            return false
        })
        #expect(abs(events[t].origin.x - next.origin.x) < 0.001)
    }

    @Test("A tempo change stands beyond the chord symbols under it")
    func tempoChangeClearsChordSymbols() throws {
        let system = try firstSystem(tune("\"D\"a3 f2e|\"G\"[Q:1/4=88]b3 a3|]"))
        let floors = try #require(system.annotationFloors)
        let baseline = try #require(floors.tempoBaseline)
        let styles = TextStyles.standard(staffSize: SVGRenderConfig().scaledStaffSize)
        let bandTop = floors.above + AnnotationBand.height(
            lines: 1, metrics: AnnotationBand.aboveMetrics(styles), staffSize: system.staffSize)
        #expect(baseline - styles.tempoChange.descent >= bandTop)
    }

    @Test("A staff with no tempo change sets no tempo line")
    func noTempoNoBaseline() throws {
        let system = try firstSystem(tune("a3 f2e|dfa b2a|]"))
        #expect(system.annotationFloors?.tempoBaseline == nil)
    }
}
