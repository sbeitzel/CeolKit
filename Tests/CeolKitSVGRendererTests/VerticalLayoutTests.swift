import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)
private let dummyFraction = Fraction(numerator: 1, denominator: 4)

private func emptyMeasure(line: Int = 0) -> Measure {
    let source = SourceRange(file: nil, byteOffset: 0, length: 0, line: line, column: 0)
    return Measure(openingBar: nil, events: [], closingBar: dummyBar, endingNumber: nil, source: source)
}

/// Distinct source range per bar, so two `BarLine`s compare unequal unless they
/// really are the same symbol.
private func barSource(byteOffset: Int) -> SourceRange {
    SourceRange(file: nil, byteOffset: byteOffset, length: 1, line: 0, column: byteOffset)
}

private func measure(opening: BarLine?, closing: BarLine) -> Measure {
    Measure(openingBar: opening, events: [], closingBar: closing,
            endingNumber: nil, source: dummyRange)
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

    // A bar line shared by two adjacent measures is resolved once, as the left
    // measure's closing bar; the right measure's inherited opening bar is dropped
    // so it is not emitted a second time on top of itself (issue #54).
    @Test func sharedBarLineIsNotResolvedTwice() {
        let shared = BarLine(kind: .double, source: barSource(byteOffset: 10))
        let system = justifiedSystem(
            measures: [
                measure(opening: nil, closing: shared),
                measure(opening: shared, closing: dummyBar)
            ],
            isLast: true
        )
        let measures = engine.layout([system]).pages[0].systems[0].measures
        #expect(measures[0].closingBar.kind == .double)
        #expect(measures[1].openingBar == nil)
    }

    // A bar that is *not* the preceding measure's closing bar is still drawn — only
    // the inherited duplicate is suppressed.
    @Test func distinctOpeningBarIsStillResolved() {
        let system = justifiedSystem(
            measures: [
                measure(opening: nil, closing: BarLine(kind: .single, source: barSource(byteOffset: 10))),
                measure(opening: BarLine(kind: .repeatStart, source: barSource(byteOffset: 20)),
                        closing: dummyBar)
            ],
            isLast: true
        )
        let measures = engine.layout([system]).pages[0].systems[0].measures
        #expect(measures[1].openingBar?.kind == .repeatStart)
    }

    // ResolvedSystem.abcLine (issue #25) is taken from the first measure's source line.
    @Test func abcLineIsFirstMeasuresSourceLine() {
        let system = justifiedSystem(
            measures: [emptyMeasure(line: 15), emptyMeasure(line: 16)],
            isLast: true
        )
        let layout = engine.layout([system])
        #expect(layout.pages[0].systems[0].abcLine == 15)
    }

    // Each system in a page reports the source line of its own first measure, not the tune's.
    @Test func abcLineDiffersAcrossSystems() {
        let s1 = justifiedSystem(measures: [emptyMeasure(line: 1)], isLast: false)
        let s2 = justifiedSystem(measures: [emptyMeasure(line: 7)], isLast: true)
        let layout = engine.layout([s1, s2])
        let systems = layout.pages[0].systems
        #expect(systems[0].abcLine == 1)
        #expect(systems[1].abcLine == 7)
    }

    // A system with no measures to resolve a line from (issue #30) inherits the previous
    // system's line plus one, instead of falling back to a hardcoded 1.
    @Test func abcLineFallsBackToPreviousLinePlusOneWhenUnresolvable() {
        let s1 = justifiedSystem(measures: [emptyMeasure(line: 20)], isLast: false)
        let s2 = justifiedSystem(measures: [], isLast: false)
        let s3 = justifiedSystem(measures: [emptyMeasure(line: 30)], isLast: true)
        let layout = engine.layout([s1, s2, s3])
        let systems = layout.pages[0].systems
        #expect(systems[0].abcLine == 20)
        #expect(systems[1].abcLine == 21)
        #expect(systems[2].abcLine == 30)
    }

    // The fallback-from-previous-line still applies to the tune-block layout overload,
    // and must survive a page break: reset per-page state must not wipe the running line.
    @Test func abcLineFallbackSurvivesPageBreakInTuneBlockLayout() {
        let a4Engine = VerticalLayoutEngine(config: a4Config, metadata: metadata)
        var systems = (0..<24).map { i in
            justifiedSystem(measures: [emptyMeasure(line: 100 + i)], isLast: false)
        }
        // A system with unresolvable content lands near a forced page break.
        systems.append(justifiedSystem(measures: [], isLast: true))
        let block = TuneBlock(systems: systems)
        let layout = a4Engine.layout([block])
        #expect(layout.pages.count >= 2)
        let allSystems = layout.pages.flatMap { $0.systems }
        let last = allSystems[allSystems.count - 1]
        let secondToLast = allSystems[allSystems.count - 2]
        #expect(last.abcLine == secondToLast.abcLine + 1)
    }
}
