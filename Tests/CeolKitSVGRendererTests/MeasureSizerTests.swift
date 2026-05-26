import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

/// Unit note length used throughout these tests: 1/8 (eighth note as the unit).
/// Quarter note = 2 units, whole note = 8 units.
private let unitNoteLength = Fraction(numerator: 1, denominator: 8)

private func note(duration: Fraction, accidental: Alteration? = nil) -> Note {
    Note(
        pitch: Pitch(step: .c, alteration: .natural, octave: 4),
        writtenAccidental: accidental,
        displayedAccidental: accidental,
        duration: duration,
        ties: .none,
        slurs: .none,
        decorations: [],
        chordSymbol: nil,
        annotations: [],
        beam: .single,
        lyric: nil,
        source: dummyRange
    )
}

private func measure(events: [Event]) -> Measure {
    Measure(
        openingBar: nil,
        events: events,
        closingBar: dummyBar,
        endingNumber: nil,
        source: dummyRange
    )
}

// MARK: - Test suite

@Suite struct MeasureSizerTests {

    let sizer: MeasureSizer

    init() throws {
        let metadata = try BravuraMetadata.load()
        sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
    }

    @Test func wholeNoteHasPositiveNaturalWidth() {
        let m = measure(events: [.note(note(duration: Fraction(numerator: 8, denominator: 1)))])
        let sized = sizer.size(m, unitNoteLength: unitNoteLength)
        #expect(sized.naturalWidth > 0)
    }

    @Test func fourQuarterNotesProduceCorrectOffsetCount() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = (0..<4).map { _ in .note(note(duration: quarter)) }
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        #expect(sized.eventOffsets.count == 4)
    }

    @Test func quarterNoteOffsetsAreStrictlyIncreasing() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = (0..<4).map { _ in .note(note(duration: quarter)) }
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        for i in 1..<sized.eventOffsets.count {
            #expect(sized.eventOffsets[i] > sized.eventOffsets[i - 1])
        }
    }

    @Test func firstEventOffsetIsZero() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = [.note(note(duration: quarter))]
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        #expect(sized.eventOffsets[0] == 0)
    }

    @Test func quarterColumnNarrowerThanWholeColumn() {
        let quarterDur = Fraction(numerator: 2, denominator: 1)
        let wholeDur   = Fraction(numerator: 8, denominator: 1)

        let quarterMeasure = measure(events: [.note(note(duration: quarterDur))])
        let wholeMeasure   = measure(events: [.note(note(duration: wholeDur))])

        let quarterSized = sizer.size(quarterMeasure, unitNoteLength: unitNoteLength)
        let wholeSized   = sizer.size(wholeMeasure,   unitNoteLength: unitNoteLength)

        // Quarter column width = naturalWidth − bar padding; whole column must be wider.
        let barPad = SVGRenderConfig().staffSize * 0.5
        let quarterCol = quarterSized.naturalWidth - barPad
        let wholeCol   = wholeSized.naturalWidth   - barPad
        #expect(quarterCol < wholeCol)
    }

    @Test func accidentalWidensColumn() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let plain  = measure(events: [.note(note(duration: quarter))])
        let sharp  = measure(events: [.note(note(duration: quarter, accidental: .sharp))])

        let plainSized = sizer.size(plain, unitNoteLength: unitNoteLength)
        let sharpSized = sizer.size(sharp, unitNoteLength: unitNoteLength)

        #expect(sharpSized.naturalWidth > plainSized.naturalWidth)
    }
}
