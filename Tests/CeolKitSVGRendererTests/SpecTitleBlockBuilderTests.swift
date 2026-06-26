import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummySrc = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)

private func makeTune(
    titles: [String] = [],
    rhythm: String? = nil,
    composer: String? = nil,
    origin: [String] = [],
    reference: Int = 0,
    tempo: Tempo? = nil
) -> Tune {
    let titleFields = titles.map { TextString(value: $0, source: dummySrc) }
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
        titles: titleFields,
        metadata: metadata,
        key: key,
        meter: .fraction(num: 4, den: 4),
        unitNoteLength: Fraction(numerator: 1, denominator: 8),
        tempo: tempo,
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

private func build(
    tune: Tune,
    writeFields: WriteFieldsConfig = .default,
    config: SVGRenderConfig = SVGRenderConfig()
) -> (rows: [ResolvedTitleRow], height: Double) {
    SpecTitleBlockBuilder(tune: tune, writeFields: writeFields, layoutConfig: config).build()
}

// MARK: - Tests

@Suite("SpecTitleBlockBuilder")
struct SpecTitleBlockBuilderTests {

    // MARK: - Empty / no title

    @Test("Tune with no titles and no other fields produces empty block")
    func noTitleNoComposerEmptyBlock() {
        let (rows, height) = build(tune: makeTune())
        #expect(rows.isEmpty)
        #expect(height == 0)
    }

    @Test("Tune with title but T disabled produces empty block")
    func titleDisabledProducesEmpty() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("T", false))
        let (rows, _) = build(tune: makeTune(titles: ["My Tune"]), writeFields: wf)
        #expect(rows.isEmpty)
    }

    // MARK: - Title rows

    @Test("Single T field produces one centered row")
    func singleTitle() {
        let tune = makeTune(titles: ["Kalabakan"])
        let (rows, height) = build(tune: tune)
        #expect(rows.count == 1)
        #expect(height > 0)
        let centerItem = rows[0].items.first { $0.anchor == .middle }
        #expect(centerItem?.text == "Kalabakan")
    }

    @Test("First title row is not italic")
    func firstTitleNotItalic() {
        let tune = makeTune(titles: ["My Tune"])
        let (rows, _) = build(tune: tune)
        let centerItem = rows[0].items.first { $0.anchor == .middle }
        #expect(centerItem?.isItalic == false)
    }

    @Test("Multiple T fields produce one row each; alternatives are italic")
    func multipleTitles() {
        let tune = makeTune(titles: ["Main Title", "Alt Title"])
        let (rows, _) = build(tune: tune)
        #expect(rows.count == 2)
        let firstCenter  = rows[0].items.first { $0.anchor == .middle }
        let secondCenter = rows[1].items.first { $0.anchor == .middle }
        #expect(firstCenter?.text  == "Main Title")
        #expect(firstCenter?.isItalic  == false)
        #expect(secondCenter?.text == "Alt Title")
        #expect(secondCenter?.isItalic == true)
    }

    // MARK: - Reference number

    @Test("X: reference appears left-aligned on the first title row when X is enabled")
    func referenceOnTitleRow() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("X", true))
        let tune = makeTune(titles: ["My Tune"], reference: 3)
        let (rows, _) = build(tune: tune, writeFields: wf)
        let leftItem = rows[0].items.first { $0.anchor == .start }
        #expect(leftItem?.text == "3")
    }

    @Test("X: reference 0 does not produce a left item even when X is enabled")
    func referenceZeroAbsent() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("X", true))
        let tune = makeTune(titles: ["My Tune"], reference: 0)
        let (rows, _) = build(tune: tune, writeFields: wf)
        let leftItem = rows[0].items.first { $0.anchor == .start }
        #expect(leftItem == nil)
    }

    // MARK: - Composer row

    @Test("C: composer appears right-aligned below the title")
    func composerRightAligned() {
        let tune = makeTune(titles: ["T"], composer: "Trad.")
        let (rows, _) = build(tune: tune)
        #expect(rows.count == 2)
        let rightItem = rows[1].items.first { $0.anchor == .end }
        #expect(rightItem?.text == "Trad.")
        #expect(rightItem?.isItalic == true)
    }

    @Test("O: origin is appended to composer in parens when both C and O are enabled")
    func originAppendedToComposer() {
        let tune = makeTune(titles: ["T"], composer: "Trad.", origin: ["Scotland"])
        let (rows, _) = build(tune: tune)
        let rightItem = rows[1].items.first { $0.anchor == .end }
        #expect(rightItem?.text == "Trad. (Scotland)")
    }

    @Test("O: origin is suppressed when O is disabled in writeFields")
    func originSuppressedWhenDisabled() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("O", false))
        let tune = makeTune(titles: ["T"], composer: "Trad.", origin: ["Scotland"])
        let (rows, _) = build(tune: tune, writeFields: wf)
        let rightItem = rows[1].items.first { $0.anchor == .end }
        #expect(rightItem?.text == "Trad.")
    }

    @Test("C field is suppressed when C is disabled in writeFields")
    func composerSuppressedWhenDisabled() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("C", false))
        let tune = makeTune(titles: ["T"], composer: "Trad.")
        let (rows, _) = build(tune: tune, writeFields: wf)
        // Only the title row; no composer row.
        #expect(rows.count == 1)
    }

    // MARK: - Rhythm row

    @Test("R: rhythm appears left-aligned when R is enabled via writeFields")
    func rhythmLeftAlignedWhenEnabled() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("R", true))
        let tune = makeTune(titles: ["T"], rhythm: "Reel")
        let (rows, _) = build(tune: tune, writeFields: wf)
        let leftItem = rows[1].items.first { $0.anchor == .start }
        #expect(leftItem?.text == "Reel")
        #expect(leftItem?.isItalic == true)
    }

    @Test("R: rhythm does not appear when R is not in writeFields")
    func rhythmAbsentByDefault() {
        let tune = makeTune(titles: ["T"], rhythm: "Reel")
        let (rows, _) = build(tune: tune)
        // Only the title row; R is not in the default set.
        #expect(rows.count == 1)
    }

    // MARK: - Rhythm + composer on same row

    @Test("R and C share a row: R left-aligned, C right-aligned")
    func rhythmAndComposerSameRow() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("R", true))
        let tune = makeTune(titles: ["T"], rhythm: "Jig", composer: "Trad.")
        let (rows, _) = build(tune: tune, writeFields: wf)
        #expect(rows.count == 2)
        let leftItem  = rows[1].items.first { $0.anchor == .start }
        let rightItem = rows[1].items.first { $0.anchor == .end }
        #expect(leftItem?.text  == "Jig")
        #expect(rightItem?.text == "Trad.")
    }

    @Test("R alone (no composer) produces a row with only a left item")
    func rhythmAloneProducesLeftItem() {
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("R", true))
        wf.apply(.writeFields("C", false))
        let tune = makeTune(titles: ["T"], rhythm: "Waltz", composer: "Trad.")
        let (rows, _) = build(tune: tune, writeFields: wf)
        // Title row + rhythm row.
        #expect(rows.count == 2)
        let rightItem = rows[1].items.first { $0.anchor == .end }
        #expect(rightItem == nil, "Composer should be suppressed")
        let leftItem = rows[1].items.first { $0.anchor == .start }
        #expect(leftItem?.text == "Waltz")
    }

    // MARK: - Tempo row (issue #26 — expected to FAIL until SpecTitleBlockBuilder reads tune.tempo)

    /// Q: is in the default write-fields set (`TCOPQwW`).  When `tune.tempo` is set,
    /// the title block must include a row showing the tempo.  Currently the builder
    /// never reads `tune.tempo`, so this test fails.
    @Test("Q: tempo appears in title block when Q is in the default writeFields set")
    func tempoAppearsInTitleBlock() {
        let tempo = Tempo(
            prelude: nil,
            beats: [Fraction(numerator: 1, denominator: 4)],
            bpm: 120,
            postlude: nil
        )
        let tune = makeTune(titles: ["T"], tempo: tempo)
        let (rows, _) = build(tune: tune)
        // Expect title row + tempo row.
        #expect(rows.count == 2,
                "Expected title row + tempo row, got \(rows.count) row(s)")
        let hasTempoText = rows.contains { row in
            row.items.contains { $0.text.contains("120") }
        }
        #expect(hasTempoText, "Title block must include the BPM value '120' from Q:1/4=120")
    }

    @Test("Q: tempo is suppressed when Q is disabled in writeFields")
    func tempoSuppressedWhenDisabled() {
        let tempo = Tempo(
            prelude: nil,
            beats: [Fraction(numerator: 1, denominator: 4)],
            bpm: 120,
            postlude: nil
        )
        var wf = WriteFieldsConfig.default
        wf.apply(.writeFields("Q", false))
        let tune = makeTune(titles: ["T"], tempo: tempo)
        let (rows, _) = build(tune: tune, writeFields: wf)
        // Only the title row; no tempo row.
        #expect(rows.count == 1, "Tempo row must be suppressed when Q is disabled")
        let hasTempoText = rows.contains { row in
            row.items.contains { $0.text.contains("120") }
        }
        #expect(!hasTempoText, "No tempo text should appear when Q is disabled")
    }

    // MARK: - Block height

    @Test("Block height is positive when rows are produced")
    func heightPositiveWithRows() {
        let tune = makeTune(titles: ["T"], composer: "X")
        let (_, height) = build(tune: tune)
        #expect(height > 0)
    }

    @Test("Block height grows with each additional row")
    func heightGrowsWithRows() {
        let oneRow  = build(tune: makeTune(titles: ["T"])).height
        let twoRows = build(tune: makeTune(titles: ["T", "Alt"])).height
        #expect(twoRows > oneRow)
    }
}
