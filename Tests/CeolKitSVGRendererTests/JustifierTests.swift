import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

private func sizedMeasure(width: Double, offsets: [Double] = [],
                           graceEventIndices: Set<Int> = []) -> SizedMeasure {
    let m = Measure(
        openingBar: nil,
        events: [],
        closingBar: dummyBar,
        endingNumber: nil,
        source: dummyRange
    )
    return SizedMeasure(measure: m, naturalWidth: width, eventOffsets: offsets,
                        graceEventIndices: graceEventIndices)
}

private func makeSystem(widths: [Double], isLast: Bool, sourceForced: Bool = false) -> System {
    System(
        measures: widths.map { sizedMeasure(width: $0) },
        isLastSystem: isLast,
        sourceForced: sourceForced
    )
}

private let usableWidth: Double = 300

// MARK: - Test suite

@Suite struct JustifierTests {

    let justifier = Justifier()

    // Non-last system: final widths sum to exactly usableWidth.
    @Test func nonLastSystemFillsUsableWidth() {
        let system = makeSystem(widths: [80, 100, 60], isLast: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        let totalFinal = result[0].measures.reduce(0.0) { $0 + $1.finalWidth }
        #expect(abs(totalFinal - usableWidth) < 1e-9)
    }

    // Non-last system: every measure's finalWidth ≥ naturalWidth.
    @Test func nonLastSystemNeverShrinksAMeasure() {
        let system = makeSystem(widths: [80, 100, 60], isLast: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        for (jm, sm) in zip(result[0].measures, system.measures) {
            #expect(jm.finalWidth >= sm.naturalWidth)
        }
    }

    // Last system without justifyLastSystem: finalWidth == naturalWidth for each measure.
    @Test func lastSystemUnchangedWhenNotJustified() {
        let system = makeSystem(widths: [80, 100, 60], isLast: true)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        for (jm, sm) in zip(result[0].measures, system.measures) {
            #expect(abs(jm.finalWidth - sm.naturalWidth) < 1e-9)
        }
    }

    // Last system with justifyLastSystem == true: sum equals usableWidth.
    @Test func lastSystemFilledWhenJustifyLastEnabled() {
        let system = makeSystem(widths: [80, 100, 60], isLast: true)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: true)
        let totalFinal = result[0].measures.reduce(0.0) { $0 + $1.finalWidth }
        #expect(abs(totalFinal - usableWidth) < 1e-9)
    }

    // eventOffsets are rescaled proportionally to finalWidth / naturalWidth.
    @Test func eventOffsetsRescaledProportionally() {
        let sized = sizedMeasure(width: 100, offsets: [0, 25, 50, 75])
        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        let jm = result[0].measures[0]
        let scale = jm.finalWidth / sized.naturalWidth
        let expected = sized.eventOffsets.map { $0 * scale }
        for (got, want) in zip(jm.eventOffsets, expected) {
            #expect(abs(got - want) < 1e-9)
        }
    }

    // isLastSystem and sourceForced flags are preserved through justification.
    @Test func metadataFlagsArePreserved() {
        let systems = [
            makeSystem(widths: [100, 100], isLast: false, sourceForced: true),
            makeSystem(widths: [80], isLast: true, sourceForced: false),
        ]
        let result = justifier.justify(systems, usableWidth: usableWidth, justifyLastSystem: false)
        #expect(result[0].sourceForced == true)
        #expect(result[0].isLastSystem == false)
        #expect(result[1].sourceForced == false)
        #expect(result[1].isLastSystem == true)
    }

    // Empty system list produces empty output.
    @Test func emptyInputProducesEmptyOutput() {
        let result = justifier.justify([], usableWidth: usableWidth, justifyLastSystem: false)
        #expect(result.isEmpty)
    }

    // MARK: - Grace-note spacing

    // When a measure contains a grace+note pair, the internal grace-to-note gap must not
    // grow during justification — only the note-to-note (elastic) gaps should expand.

    @Test func graceToNoteGapIsPreservedWhenMeasureIsStretched() {
        // Layout: grace at 7, paired note at 17 (fixed gap = 10), standalone note at 27.
        // Stretch naturalWidth 40 → finalWidth 60.
        let naturalGap = 10.0
        let sized = sizedMeasure(width: 40, offsets: [7, 17, 27], graceEventIndices: [0])
        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let result = justifier.justify([system], usableWidth: 60, justifyLastSystem: false)
        let jm = result[0].measures[0]

        let stretchedGap = jm.eventOffsets[1] - jm.eventOffsets[0]
        #expect(abs(stretchedGap - naturalGap) < 1e-9)
    }

    @Test func elasticSlackGoesOnlyToNoteToNoteGapNotGraceToNoteGap() {
        // Same layout: grace(7) → note(17, fixed gap 10) → standalone(27, elastic gap 10).
        // With the grace gap frozen, all slack must flow to the elastic note-to-note gap.
        //
        // elasticNatural = 40 - 7 - 10 = 23
        // elasticScale   = (60 - 7 - 10) / 23 = 43/23
        // new offset[2]  = 7 + 10 + (27 - 7 - 10) * (43/23) = 17 + 10*(43/23)
        let sized = sizedMeasure(width: 40, offsets: [7, 17, 27], graceEventIndices: [0])
        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let result = justifier.justify([system], usableWidth: 60, justifyLastSystem: false)
        let jm = result[0].measures[0]

        let elasticScale = (60.0 - 7.0 - 10.0) / (40.0 - 7.0 - 10.0)   // 43/23
        let expectedNote = 7.0 + 10.0 + 10.0 * elasticScale              // grace base + fixed gap + stretched elastic
        #expect(abs(jm.eventOffsets[2] - expectedNote) < 1e-9)
        // The elastic gap grew; the frozen gap did not.
        #expect(jm.eventOffsets[2] - jm.eventOffsets[1] > jm.eventOffsets[1] - jm.eventOffsets[0])
    }

    @Test func multipleGracePairsAllKeepFixedGaps() {
        // Two grace+note pairs with a standalone note between them.
        // Layout (natural): grace0(7) → note0(14, gap 7) → standalone(24) → grace1(34) → note1(39, gap 5)
        // naturalWidth = 50.  Stretch to 70.
        //
        // fixedTotal = 7 + 5 = 12
        // elasticNatural = 50 - 7 - 12 = 31
        // elasticScale   = (70 - 7 - 12) / 31 = 51/31
        let sized = sizedMeasure(width: 50, offsets: [7, 14, 24, 34, 39],
                                  graceEventIndices: [0, 3])
        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let result = justifier.justify([system], usableWidth: 70, justifyLastSystem: false)
        let jm = result[0].measures[0]

        // Both fixed gaps must be preserved exactly.
        #expect(abs((jm.eventOffsets[1] - jm.eventOffsets[0]) - 7.0) < 1e-9)
        #expect(abs((jm.eventOffsets[4] - jm.eventOffsets[3]) - 5.0) < 1e-9)

        // Elastic gaps (standalone gap and the gap from note0 to grace1) must have grown.
        #expect(jm.eventOffsets[2] - jm.eventOffsets[1] > 10.0)
        #expect(jm.eventOffsets[3] - jm.eventOffsets[2] > 10.0)
    }

    @Test func measureSizerSetsGraceEventIndicesForPairedGrace() throws {
        // Verify the MeasureSizer correctly marks grace event indices so the justifier
        // can find them without additional bookkeeping.
        let metadata = try BravuraMetadata.load()
        let sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
        let gNote = Note(
            pitch: Pitch(step: .g, alteration: .natural, octave: 4),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 2),
            ties: .none, slurs: .none, decorations: [], chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let grace = GraceGroup(kind: .appoggiatura, notes: [gNote], source: dummyRange)
        let principal = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 4),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 2, denominator: 1),
            ties: .none, slurs: .none, decorations: [], chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let m = Measure(openingBar: nil,
                        events: [.grace(grace), .note(principal)],
                        closingBar: dummyBar, endingNumber: nil, source: dummyRange)
        let sized = sizer.size(m, unitNoteLength: Fraction(numerator: 1, denominator: 8))

        // Grace is the first event (index 0); it must appear in graceEventIndices.
        #expect(sized.graceEventIndices.contains(0))
        // The paired note (index 1) is NOT a grace event.
        #expect(!sized.graceEventIndices.contains(1))
    }
}
