import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let config   = SVGRenderConfig()
private let metadata = try! BravuraMetadata.load()

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

private func parseMeasure(_ abc: String) -> Measure {
    let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
    return tune.voices[0].staves[0].measures[0]
}

/// Issue #75: every event carries the voice it was written by, from the sizer through to
/// the resolved layout.  Behaviour-neutral on its own — this is the seam the shared-staff
/// work (§11.1 `( … )`) hangs on, and the goldens assert that nothing about the page moved.
@Suite("Event Voice Tags")
struct EventVoiceTagTests {

    // MARK: - Pass 1

    @Test("The sizer tags every event with the voice it sized for")
    func sizerTagsEveryEvent() {
        let measure = parseMeasure("X:1\nL:1/8\nK:C\nCDEF GABc|\n")
        let sizer   = MeasureSizer(config: config, metadata: metadata)
        let sized   = sizer.size(measure, unitNoteLength: Fraction(numerator: 1, denominator: 8),
                                 voiceIndex: 3)

        #expect(sized.eventVoiceIndices.count == sized.eventOffsets.count)
        #expect(sized.eventVoiceIndices.allSatisfy { $0 == 3 })
    }

    @Test("A measure sized without a voice belongs to voice 0")
    func sizerDefaultsToVoiceZero() {
        let measure = parseMeasure("X:1\nL:1/8\nK:C\nCDEF|\n")
        let sized   = MeasureSizer(config: config, metadata: metadata)
            .size(measure, unitNoteLength: Fraction(numerator: 1, denominator: 8))
        #expect(sized.eventVoiceIndices == [0, 0, 0, 0])
    }

    @Test("A hand-built SizedMeasure gets a table parallel to its offsets")
    func handBuiltMeasureIsStillParallel() {
        let sized = SizedMeasure(measure: Measure(openingBar: nil, events: [], closingBar: dummyBar,
                                                  endingNumber: nil, source: dummyRange),
                                 naturalWidth: 100, eventOffsets: [0, 10, 20])
        #expect(sized.eventVoiceIndices == [0, 0, 0])
    }

    // MARK: - Pass 3

    /// The tags have to come through justification intact, and specifically alongside the
    /// grace pairing: `stretchOffsets` treats a grace event and its principal note as one
    /// unit, so a measure with grace notes is the case where an index-keyed side table is
    /// most likely to slip out of step with the offsets.
    @Test("Justification moves the events and keeps their tags")
    func justificationPreservesTags() {
        let measure = parseMeasure("X:1\nL:1/8\nK:C\n{g}A B {ge}c d|\n")
        let sized   = MeasureSizer(config: config, metadata: metadata)
            .size(measure, unitNoteLength: Fraction(numerator: 1, denominator: 8), voiceIndex: 1)
        #expect(!sized.graceEventIndices.isEmpty)

        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let justified = Justifier().justify([system], usableWidth: sized.naturalWidth * 2,
                                            justifyLastSystem: true)
        let jm = justified[0].measures[0]

        #expect(jm.eventOffsets != sized.eventOffsets)   // it really did stretch
        #expect(jm.eventOffsets.count == jm.eventVoiceIndices.count)
        #expect(jm.eventVoiceIndices.allSatisfy { $0 == 1 })
    }

    // MARK: - Pass 4

    @Test("Every resolved event carries a voice index")
    func resolvedEventsCarryTheTag() {
        let measure = parseMeasure("X:1\nL:1/8\nK:C\nCDEF GABc|\n")
        let sized   = MeasureSizer(config: config, metadata: metadata)
            .size(measure, unitNoteLength: Fraction(numerator: 1, denominator: 8), voiceIndex: 2)
        let jm = JustifiedMeasure(source: sized, finalWidth: sized.naturalWidth,
                                  eventOffsets: sized.eventOffsets)
        let system = JustifiedSystem(measures: [jm], isLastSystem: true, sourceForced: false)
        let layout = VerticalLayoutEngine(config: config, metadata: metadata).layout([system])

        let events = layout.pages.flatMap(\.systems).flatMap(\.measures).flatMap(\.events)
        #expect(events.count == sized.eventOffsets.count)
        #expect(events.allSatisfy { $0.voiceIndex == 2 })
    }

    // MARK: - End to end

    /// The renderer's own chain, run over a two-voice tune: each staff's events must come
    /// out tagged with that staff's index and no other.
    @Test("Each staff of a multi-voice system tags its events with its own voice")
    func multiVoiceTunePipeline() throws {
        let abc = """
            X:1
            T:Two Voices
            M:4/4
            L:1/8
            K:D
            V:M1
            V:M2
            [V:M1] abcd efga | bage dcBA |
            [V:M2] ABcd efga | bage dcBA |
            """
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        var diagnostics: [Diagnostic] = []
        let voices = VoiceSelector.select(from: tune.voices, plan: nil, into: &diagnostics).voices
        #expect(voices.count == 2)

        let sizer  = MeasureSizer(config: config, metadata: metadata)
        let staves = VoiceAligner.align(voices, into: &diagnostics)
        var columnsPerVoice = [[SizedMeasure]](repeating: [], count: voices.count)
        var breaks: [ScoreLineBreak?] = []
        for stave in staves {
            for column in 0..<stave.measureCount {
                breaks.append(nil)
                for v in voices.indices {
                    columnsPerVoice[v].append(
                        sizer.size(stave.measures[v][column],
                                   unitNoteLength: tune.effectiveUnitNoteLength(for: voices[v]),
                                   voiceIndex: v))
                }
            }
        }

        let lines = voices.indices.map { LineBreaker.VoiceLine(measures: columnsPerVoice[$0]) }
        let groups = LineBreaker().breakIntoGroups(lines, breaks: breaks, usableWidth: 500)
        let justified = Justifier().justifyGroups(groups, usableWidth: 500, justifyLastSystem: false)
        let block  = TuneBlock(systemGroups: justified)
        let layout = VerticalLayoutEngine(config: config, metadata: metadata).layout([block])

        let staffSystems = layout.pages.flatMap(\.systems)
        #expect(staffSystems.count == 2)
        for system in staffSystems {
            let group = try #require(system.staffGroup)
            let events = system.measures.flatMap(\.events)
            #expect(!events.isEmpty)
            #expect(events.allSatisfy { $0.voiceIndex == group.index })
        }
    }
}
