import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)
private let dummyFraction = Fraction(numerator: 1, denominator: 4)

private func emptyMeasure() -> Measure {
    Measure(openingBar: nil, events: [], closingBar: dummyBar, endingNumber: nil, source: dummyRange)
}

private func measureWith(events: [Event]) -> Measure {
    Measure(openingBar: nil, events: events, closingBar: dummyBar, endingNumber: nil, source: dummyRange)
}

private func justifiedSystem(measures: [Measure] = [], isLast: Bool = false) -> JustifiedSystem {
    let jm = measures.map { m in
        JustifiedMeasure(
            source: SizedMeasure(measure: m, naturalWidth: 100, eventOffsets: Array(repeating: 0, count: m.events.count)),
            finalWidth: 100,
            eventOffsets: Array(repeating: 0, count: m.events.count)
        )
    }
    return JustifiedSystem(measures: jm, isLastSystem: isLast, sourceForced: false)
}

private func noteEvent(step: DiatonicStep, octave: Int, lyric: LyricSyllable? = nil) -> Event {
    let pitch = Pitch(step: step, alteration: .natural, octave: octave)
    let note = Note(
        pitch: pitch,
        writtenAccidental: nil,
        displayedAccidental: nil,
        duration: dummyFraction,
        ties: .none,
        slurs: .none,
        decorations: [],
        chordSymbol: nil,
        annotations: [],
        beam: .single,
        lyric: lyric,
        source: dummyRange
    )
    return .note(note)
}

private let defaultConfig = SVGRenderConfig()
private let a4Config      = SVGRenderConfig(pageSize: .a4)
private let metadata      = try! BravuraMetadata.load()

// MARK: - Tests

@Suite struct VerticalLayoutTests {

    let engine = VerticalLayoutEngine(config: defaultConfig, metadata: metadata)

    // staffHeight is exactly 4 × staffSize.
    @Test func staffHeightIsFourStaffSpaces() {
        let system = justifiedSystem(measures: [emptyMeasure()], isLast: true)
        let layout = engine.layout([system])
        let s = layout.pages[0].systems[0]
        #expect(abs(s.staffHeight - 4 * defaultConfig.staffSize) < 1e-9)
    }

    // A note at E6 (3rd ledger line above treble staff) → extraAbove ≥ 3 × staffSize.
    @Test func highNoteProducesExtraAbove() {
        let event = noteEvent(step: .e, octave: 6)      // staff position 14 → 3 ledger lines
        let m = measureWith(events: [event])
        let system = justifiedSystem(measures: [m], isLast: true)
        let layout = engine.layout([system])
        let s = layout.pages[0].systems[0]
        #expect(s.extraAbove >= 3 * defaultConfig.staffSize)
    }

    // A note with a lyric → extraBelow ≥ 2 × staffSize.
    @Test func noteWithLyricProducesExtraBelow() {
        let lyric = LyricSyllable.text(TextString(value: "la", source: dummyRange), connection: .wordEnd)
        let event = noteEvent(step: .c, octave: 5, lyric: lyric)
        let m = measureWith(events: [event])
        let system = justifiedSystem(measures: [m], isLast: true)
        let layout = engine.layout([system])
        let s = layout.pages[0].systems[0]
        #expect(s.extraBelow >= 2 * defaultConfig.staffSize)
    }

    // Two consecutive systems: second system's origin.y > first system's bottom edge.
    @Test func systemsStackWithoutOverlap() {
        let s1 = justifiedSystem(measures: [emptyMeasure()], isLast: false)
        let s2 = justifiedSystem(measures: [emptyMeasure()], isLast: true)
        let layout = engine.layout([s1, s2])
        let page = layout.pages[0]
        #expect(page.systems.count == 2)
        let first = page.systems[0]
        let second = page.systems[1]
        #expect(second.origin.y > first.origin.y + first.totalHeight)
    }

    // Four measures in one system on A4 → single page.
    @Test func fourMeasuresFitOnOnePage() throws {
        let a4Engine = VerticalLayoutEngine(config: a4Config, metadata: metadata)
        let system = justifiedSystem(
            measures: (0..<4).map { _ in emptyMeasure() },
            isLast: true
        )
        let layout = a4Engine.layout([system])
        #expect(layout.pages.count == 1)
    }

    // Enough systems to overflow a page → at least 2 pages.
    @Test func manySystemsOverflowToTwoPages() {
        let a4Engine = VerticalLayoutEngine(config: a4Config, metadata: metadata)
        // On A4 with default staff/system gap, each system is about 40.5pt (staffHeight=18 + gap=22.5).
        // Usable height ≈ 770pt → need ~20+ systems to overflow.
        let systems = (0..<25).map { i in
            justifiedSystem(measures: [emptyMeasure()], isLast: i == 24)
        }
        let layout = a4Engine.layout(systems)
        #expect(layout.pages.count >= 2)
    }

    // Measure origins increase monotonically left-to-right within a system.
    @Test func measureOriginsIncreaseLeftToRight() {
        let system = justifiedSystem(
            measures: (0..<3).map { _ in emptyMeasure() },
            isLast: true
        )
        let layout = engine.layout([system])
        let measures = layout.pages[0].systems[0].measures
        for i in 1..<measures.count {
            #expect(measures[i].origin.x > measures[i - 1].origin.x)
        }
    }

    // Closing bar of each measure is at origin.x + width.
    @Test func closingBarAlignedWithMeasureEdge() {
        let system = justifiedSystem(
            measures: (0..<2).map { _ in emptyMeasure() },
            isLast: true
        )
        let layout = engine.layout([system])
        for m in layout.pages[0].systems[0].measures {
            #expect(abs(m.closingBar.x - (m.origin.x + m.width)) < 1e-9)
        }
    }
}
