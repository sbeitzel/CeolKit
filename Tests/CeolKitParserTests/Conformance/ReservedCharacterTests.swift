// Reserved character conformance tests. ABC §8.1.
// The characters # * ; ? @ are reserved in music code for future use.
// When they appear between note groups the parser must treat them as
// Token.unknown, emit a diagnostic, and still produce the correct notes.
//
// The spec gives this verbatim example (§8.1 / CeolKit spec §5.6):
//
//   @a !pp! #bc2/3* [K:C#] de?f "@this $2was difficult to parse?" y |**
//
// must parse to the same musical events as:
//
//   a !pp! bc2/3 [K:C#] def "@this $2was difficult to parse?" y |
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Reserved Characters (§8.1)")
struct ReservedCharacterTests {

    let cleanSource = """
    X:1
    T:Clean
    M:4/4
    L:1/8
    K:C
    a !pp! bc2/3 [K:C#] def "@this $2was difficult to parse?" y |
    """

    let dirtySource = """
    X:1
    T:Dirty
    M:4/4
    L:1/8
    K:C
    @a !pp! #bc2/3* [K:C#] de?f "@this $2was difficult to parse?" y |**
    """

    @Test("Clean source parses to a score with one tune")
    func cleanParsesOK() {
        let result = parse(cleanSource)
        #expect(result.score.tunes.count == 1)
        #expect(result.score.errorDiagnostics.isEmpty)
    }

    @Test("Dirty source also parses to a score (no crash)")
    func dirtyStillProducesScore() {
        let result = parse(dirtySource)
        // Always returns a Score, never crashes
        #expect(result.score.tunes.count == 1)
    }

    @Test("Dirty source emits diagnostics for reserved characters")
    func dirtyEmitsDiagnostics() {
        let result = parse(dirtySource)
        // @, #, *, ? at note-level should emit at least one diagnostic
        let reservedDiags = result.score.diagnostics.filter {
            $0.code == .reservedCharacter
        }
        #expect(!reservedDiags.isEmpty)
    }

    @Test("Both sources produce the same note sequence (a, b, c, d, e, f)")
    func sameNoteSequence() {
        let clean = parse(cleanSource)
        let dirty = parse(dirtySource)

        let cleanNotes = clean.score.firstTune?.singleVoiceMeasures
            .flatMap(\.noteEvents).map(\.pitch.step) ?? []
        let dirtyNotes = dirty.score.firstTune?.singleVoiceMeasures
            .flatMap(\.noteEvents).map(\.pitch.step) ?? []

        // Both should have the same sequence of note steps
        #expect(cleanNotes == dirtyNotes)
    }

    @Test("Both sources produce the same note count")
    func sameNoteCount() {
        let clean = parse(cleanSource)
        let dirty = parse(dirtySource)

        let cleanCount = clean.score.firstTune?.singleVoiceMeasures
            .flatMap(\.noteEvents).count ?? 0
        let dirtyCount = dirty.score.firstTune?.singleVoiceMeasures
            .flatMap(\.noteEvents).count ?? 0

        #expect(cleanCount == dirtyCount)
    }

    @Test("Both sources have the same pp decoration on the 'a' note")
    func sameDecoration() {
        let clean = parse(cleanSource)
        let dirty = parse(dirtySource)

        let cleanFirst = clean.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        let dirtyFirst = dirty.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first

        #expect(cleanFirst?.pitch.step == .a)
        #expect(dirtyFirst?.pitch.step == .a)
        #expect(cleanFirst?.decorations.contains(.pp) == true)
        #expect(dirtyFirst?.decorations.contains(.pp) == true)
    }

    @Test("Both sources produce the same inline key change [K:C#]")
    func sameInlineKeyChange() {
        let clean = parse(cleanSource)
        let dirty = parse(dirtySource)

        // After [K:C#], notes d, e, f should be in C# context.
        // The d, e, f that follow [K:C#] should have C# key applied.
        // In C# major, every note has a sharp — so f should have alteration +1/1.
        let cleanAllNotes = clean.score.firstTune?.singleVoiceMeasures.flatMap(\.noteEvents) ?? []
        let dirtyAllNotes = dirty.score.firstTune?.singleVoiceMeasures.flatMap(\.noteEvents) ?? []

        // Both should have an f note with sharp alteration (from K:C#)
        let cleanFSharp = cleanAllNotes.first(where: {
            $0.pitch.step == .f && $0.pitch.alteration == Alteration(numerator: 1, denominator: 1)
        })
        let dirtyFSharp = dirtyAllNotes.first(where: {
            $0.pitch.step == .f && $0.pitch.alteration == Alteration(numerator: 1, denominator: 1)
        })

        #expect(cleanFSharp != nil)
        #expect(dirtyFSharp != nil)
    }

    @Test("Strict mode escalates reserved character diagnostics to errors")
    func strictModeReservedCharIsError() {
        let options = ParseOptions(strictRecovery: true)
        let result = parse(dirtySource, options: options)
        // In strict mode, reserved characters produce errors, not just info
        let errors = result.score.diagnostics.filter {
            $0.code == .reservedCharacter && $0.severity == .error
        }
        #expect(!errors.isEmpty)
    }

    // MARK: Reserved characters inside strings are safe

    @Test("Reserved characters inside annotation strings are not flagged")
    func reservedInAnnotationIsOK() {
        let source = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        "@this $2was difficult to parse?"C|
        """
        let result = parse(source)
        // The entire string "@this $2..." is a text annotation, not music code.
        // No .reservedCharacter diagnostics should be emitted for it.
        let reserved = result.score.diagnostics.filter { $0.code == .reservedCharacter }
        #expect(reserved.isEmpty)
    }
}
