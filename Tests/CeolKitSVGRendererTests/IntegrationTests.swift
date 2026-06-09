import Testing
import SnapshotTesting
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Score construction helpers

private let dummyRange   = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let singleBar    = BarLine(kind: .single, source: dummyRange)
private let finalBar     = BarLine(kind: .final,  source: dummyRange)

private func makeNote(step: DiatonicStep, octave: Int, duration: Fraction,
                      beam: BeamState = .single) -> Note {
    Note(
        pitch:               Pitch(step: step, alteration: .natural, octave: octave),
        writtenAccidental:   nil,
        displayedAccidental: nil,
        duration:            duration,
        ties:                .none,
        slurs:               SlurState(opens: 0, closes: 0),
        decorations:         [],
        chordSymbol:         nil,
        annotations:         [],
        beam:                beam,
        lyric:               nil,
        source:              dummyRange
    )
}

private func makeMeasure(events: [Event], closing: BarLine = singleBar) -> Measure {
    Measure(openingBar: nil, events: events, closingBar: closing,
            endingNumber: nil, source: dummyRange)
}

private func makeVoice(id: String, measures: [Measure]) -> Voice {
    Voice(
        id: .named(id),
        properties: VoiceProperties(
            clef:            ClefSpec(clef: .treble, octaveShift: 0),
            transposition:   .none,
            staffProperties: StaffProperties(staffLines: 5, scale: nil),
            name:            nil,
            subname:         nil,
            stemDirection:   .auto,
            middleNote:      nil
        ),
        staves:     [Staff(measures: measures, overlays: [])],
        directives: [],
        source:     dummyRange
    )
}

private func makeTune(
    ref: Int = 1,
    title: String = "Test",
    voices: [Voice],
    unitNoteLength: Fraction,
    meter: Meter = .fraction(num: 4, den: 4)
) -> Tune {
    let key = KeySignature(
        tonic:           PitchClass(step: .c, alteration: .natural),
        mode:            .major,
        modifications:   [],
        explicit:        false,
        clef:            ClefSpec(clef: .treble, octaveShift: 0),
        transposition:   .none,
        staffProperties: StaffProperties(staffLines: 5, scale: nil),
        source:          dummyRange
    )
    let meta = TuneMetadata(
        composer: nil, origin: [], area: nil, book: nil, discography: nil,
        fileURL: nil, group: nil, history: [], notes: nil, source: nil,
        rhythm: nil, transcription: nil
    )
    return Tune(
        reference:      ref,
        titles:         [TextString(value: title, source: dummyRange)],
        metadata:       meta,
        key:            key,
        meter:          meter,
        unitNoteLength: unitNoteLength,
        tempo:          nil,
        parts:          nil,
        voices:         voices,
        userSymbols:    [:],
        macros:         [],
        directives:     [],
        source:         dummyRange
    )
}

private func makeScore(tunes: [Tune]) -> Score {
    Score(
        source:      dummyRange,
        dialect:     .loose,
        creator:     nil,
        charset:     nil,
        tunes:       tunes,
        freeText:    [],
        typesetText: [],
        diagnostics: []
    )
}

// MARK: - Shared score fixtures

/// One tune, one voice, four C4 quarter notes in 4/4 (UNL = 1/4).
private func fourQuarterNoteScore() -> Score {
    let quarter = Fraction(numerator: 1, denominator: 1)
    let events: [Event] = [
        .note(makeNote(step: .c, octave: 4, duration: quarter)),
        .note(makeNote(step: .d, octave: 4, duration: quarter)),
        .note(makeNote(step: .e, octave: 4, duration: quarter)),
        .note(makeNote(step: .f, octave: 4, duration: quarter)),
    ]
    let voice = makeVoice(id: "1", measures: [makeMeasure(events: events, closing: finalBar)])
    let tune  = makeTune(voices: [voice], unitNoteLength: Fraction(numerator: 1, denominator: 4))
    return makeScore(tunes: [tune])
}

/// "Simple jig": 6/8, UNL = 1/8, two measures of G4 A4 B4 C5 D5 E5.
private func simpleJigScore() -> Score {
    let eighth = Fraction(numerator: 1, denominator: 1)  // 1 × (1/8) = eighth note

    func jigMeasure(closing: BarLine) -> Measure {
        let notes: [Event] = [
            .note(makeNote(step: .g, octave: 4, duration: eighth, beam: .start)),
            .note(makeNote(step: .a, octave: 4, duration: eighth, beam: .middle)),
            .note(makeNote(step: .b, octave: 4, duration: eighth, beam: .middle)),
            .note(makeNote(step: .c, octave: 5, duration: eighth, beam: .middle)),
            .note(makeNote(step: .d, octave: 5, duration: eighth, beam: .middle)),
            .note(makeNote(step: .e, octave: 5, duration: eighth, beam: .end)),
        ]
        return makeMeasure(events: notes, closing: closing)
    }

    let voice = makeVoice(id: "1", measures: [
        jigMeasure(closing: singleBar),
        jigMeasure(closing: finalBar),
    ])
    let tune = makeTune(
        title:          "Simple Jig",
        voices:         [voice],
        unitNoteLength: Fraction(numerator: 1, denominator: 8),
        meter:          .fraction(num: 6, den: 8)
    )
    return makeScore(tunes: [tune])
}

// MARK: - Integration test suite

@Suite struct IntegrationTests {

    // MARK: Basic rendering

    @Test func fourQuarterNoteScoreRendersToOneElement() throws {
        let pages = try SVGRenderer().render(fourQuarterNoteScore())
        #expect(pages.count == 1)
    }

    @Test func eachPageIsValidSVG() throws {
        let pages = try SVGRenderer().render(fourQuarterNoteScore())
        for page in pages {
            #expect(page.hasPrefix("<svg "))
            #expect(page.contains("viewBox="))
            #expect(page.contains("</svg>"))
        }
    }

    // MARK: Page overflow

    /// Three voices on a 100 pt-tall page forces a second page.
    ///
    /// Geometry: usable height = 80 pt; staffHeight = 18; systemGap = 22.5.
    ///   System 1 bottom: 10 + 18 = 28 pt.
    ///   System 2 bottom: 28 + 22.5 + 18 = 68.5 pt.
    ///   System 3 top:   68.5 + 22.5 = 91 pt + 18 = 109 pt > 90 → next page.
    @Test func systemsOverflowingPageProduceMultipleElements() throws {
        let quarter = Fraction(numerator: 1, denominator: 1)
        let measure = makeMeasure(events: [.note(makeNote(step: .c, octave: 4, duration: quarter))])
        let voices  = (1...3).map { i in makeVoice(id: "\(i)", measures: [measure]) }
        let tune    = makeTune(voices: voices, unitNoteLength: Fraction(numerator: 1, denominator: 4))
        let score   = makeScore(tunes: [tune])
        let config  = SVGRenderConfig(
            pageSize: PageSize(width: 400, height: 100),
            margins:  EdgeInsets(top: 10, bottom: 10, left: 10, right: 10)
        )
        let pages = try SVGRenderer(config: config).render(score)
        #expect(pages.count > 1)
    }

    // MARK: Multi-tune

    /// Two tunes each produce at least one staff system;
    /// the heuristic is ≥ 10 `<line>` elements (5 per system × 2 systems).
    @Test func twoTunesProduceContentForBoth() throws {
        let quarter = Fraction(numerator: 1, denominator: 1)
        let events: [Event] = [.note(makeNote(step: .c, octave: 4, duration: quarter))]
        let tune1 = makeTune(ref: 1, title: "Tune A",
                             voices: [makeVoice(id: "1", measures: [makeMeasure(events: events)])],
                             unitNoteLength: Fraction(numerator: 1, denominator: 4))
        let tune2 = makeTune(ref: 2, title: "Tune B",
                             voices: [makeVoice(id: "1", measures: [makeMeasure(events: events)])],
                             unitNoteLength: Fraction(numerator: 1, denominator: 4))
        let pages    = try SVGRenderer().render(makeScore(tunes: [tune1, tune2]))
        let combined = pages.joined()
        // 2 tunes × 1 voice each = 2 systems × 5 staff lines = ≥ 10 lines.
        let lineCount = combined.components(separatedBy: "<line ").count - 1
        #expect(lineCount >= 10)
    }

    // MARK: Snapshot

    @Test func simpleJigScoreMatchesSnapshot() throws {
        let svg = try SVGRenderer().render(simpleJigScore())[0]

        // Strip the embedded Bravura base64 blob so the snapshot stays small
        // and diffs focus on SVG structure rather than font data.
        let sanitized = svg.replacing(
            /data:font\/otf;base64,[A-Za-z0-9+\/=]+/,
            with: "data:font/otf;base64,<BRAVURA>"
        )

        assertSnapshot(of: sanitized, as: .lines)
    }
}
