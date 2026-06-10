import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummySrc = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)

private func makeTune(
    title: String? = nil,
    rhythm: String? = nil,
    composer: String? = nil,
    reference: Int = 0,
    origin: [String] = []
) -> Tune {
    let titleField  = title.map    { TextString(value: $0, source: dummySrc) }
    let rhythmField = rhythm.map   { TextString(value: $0, source: dummySrc) }
    let compField   = composer.map { TextString(value: $0, source: dummySrc) }
    let metadata = TuneMetadata(
        composer: compField,
        origin: origin,
        area: nil,
        book: nil,
        discography: nil,
        fileURL: nil,
        group: nil,
        history: [],
        notes: nil,
        source: nil,
        rhythm: rhythmField,
        transcription: nil
    )
    let key = KeySignature(
        tonic: PitchClass(step: .c, alteration: .natural),
        mode: .major,
        modifications: [],
        explicit: false,
        clef: ClefSpec(clef: .treble, octaveShift: 0),
        transposition: .none,
        staffProperties: StaffProperties(staffLines: 5, scale: nil),
        source: dummySrc
    )
    return Tune(
        reference: reference,
        titles: titleField.map { [$0] } ?? [],
        metadata: metadata,
        key: key,
        meter: .fraction(num: 4, den: 4),
        unitNoteLength: Fraction(numerator: 1, denominator: 8),
        tempo: nil,
        parts: nil,
        voices: [Voice(
            id: .named("1"),
            properties: VoiceProperties(
                clef: ClefSpec(clef: .treble, octaveShift: 0),
                transposition: .none,
                staffProperties: StaffProperties(staffLines: 5, scale: nil),
                name: nil, subname: nil, stemDirection: .auto, middleNote: nil
            ),
            staves: [Staff(measures: [], overlays: [])],
            directives: [],
            source: dummySrc
        )],
        userSymbols: [:],
        macros: [],
        directives: [],
        source: dummySrc
    )
}

// MARK: - Tests

@Suite("TitleResolver")
struct TitleResolverTests {

    @Test("T field resolves to first title")
    func titleField() {
        let tune = makeTune(title: "Kalabakan")
        let spec = TitleFormatParser.parse("T")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].center == "Kalabakan")
        #expect(rows[0].left == nil)
        #expect(rows[0].right == nil)
    }

    @Test("R field resolves to rhythm")
    func rhythmField() {
        let tune = makeTune(rhythm: "Reel")
        let spec = TitleFormatParser.parse("R-1")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].left == "Reel")
    }

    @Test("C field resolves to composer")
    func composerField() {
        let tune = makeTune(composer: "Trad.")
        let spec = TitleFormatParser.parse("C1")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].right == "Trad.")
    }

    @Test("X field resolves to reference number")
    func referenceField() {
        let tune = makeTune(reference: 42)
        let spec = TitleFormatParser.parse("X")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].center == "42")
    }

    @Test("X field with reference 0 produces nil (field absent)")
    func referenceZeroAbsent() {
        let tune = makeTune(reference: 0)
        let spec = TitleFormatParser.parse("X")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.isEmpty)
    }

    @Test("Unknown field code produces nil (entry silently absent)")
    func unknownFieldCode() {
        let tune = makeTune(title: "My Tune")
        let spec = TitleFormatParser.parse("Q")  // Q is not a metadata field
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.isEmpty)
    }

    @Test("Box with all-nil fields is dropped")
    func allNilBoxDropped() {
        let tune = makeTune(title: "My Tune")  // no rhythm
        let spec = TitleFormatParser.parse("T0, R-1")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].center == "My Tune")
    }

    @Test("Two-box format produces two rows when both have content")
    func twoBoxesBothContent() {
        let tune = makeTune(title: "My Tune", rhythm: "Jig", composer: "Trad.")
        let spec = TitleFormatParser.parse("T0, R-1 C1")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 2)
        #expect(rows[0].center == "My Tune")
        #expect(rows[1].left   == "Jig")
        #expect(rows[1].right  == "Trad.")
    }

    @Test("concatWithPrevious joins X and T inline (center zone)")
    func concatXplusT() {
        let tune = makeTune(title: "Kalabakan", reference: 1)
        let spec = TitleFormatParser.parse("X+T")
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        #expect(rows[0].center == "1 Kalabakan")
    }

    @Test("concatWithPrevious with no previous value in zone starts a new item")
    func concatNoPreviousInZone() {
        let tune = makeTune(title: "My Tune")  // X has no value (reference = 0)
        let spec = TitleFormatParser.parse("X+T")  // X is nil, T center concat=true
        let rows = TitleResolver(tune: tune).resolve(spec)
        #expect(rows.count == 1)
        // X is nil, so T falls back to a standalone item
        #expect(rows[0].center == "My Tune")
    }
}
