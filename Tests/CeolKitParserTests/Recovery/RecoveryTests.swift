// Recovery contract tests — verifies the parser always produces a Score and
// attaches diagnostics instead of crashing or silently dropping content.
// Recovery contract per CLAUDE.md §Architecture → Recovery contract.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Recovery")
struct RecoveryTests {

    // MARK: - Always returns a Score

    @Test("Empty input returns a Score without crashing")
    func emptyInputReturnsScore() {
        let result = parse("")
        // Score is always returned — the type-level guarantee
        _ = result.score
    }

    @Test("Whitespace-only input returns a Score")
    func whitespaceInputReturnsScore() {
        let result = parse("   \n\t\n  ")
        _ = result.score
    }

    @Test("Comment-only input returns a Score with no tunes")
    func commentOnlyInput() {
        let result = parse("% This is a comment\n% Another comment\n")
        #expect(result.score.tunes.isEmpty)
    }

    @Test("Random garbage characters return a Score without crashing")
    func garbageInputReturnsScore() {
        let result = parse("@#$%^&*()!!!")
        _ = result.score
    }

    @Test("Unicode garbage returns a Score without crashing")
    func unicodeGarbageReturnsScore() {
        let result = parse("€£¥\u{0000}\u{FFFD}~`")
        _ = result.score
    }

    // MARK: - Missing required fields

    @Test("Tune without K: emits missingRequiredField")
    func missingKeySignatureEmitsDiagnostic() {
        let abc = "X:1\nT:No Key\nM:4/4\nL:1/4\nCDEF|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .missingRequiredField }
        #expect(!errors.isEmpty)
    }

    @Test("Tune without K: still produces a Tune (synthetic default key)")
    func missingKeySignatureProducesTune() {
        let abc = "X:1\nT:No Key\nM:4/4\nL:1/4\nCDEF|\n"
        let result = parse(abc)
        #expect(result.score.tunes.count == 1)
    }

    @Test("Tune without K: uses synthetic default: C major")
    func missingKeySignatureDefaultsToC() {
        let abc = "X:1\nT:No Key\nM:4/4\nL:1/4\nCDEF|\n"
        let result = parse(abc)
        guard let tune = result.score.firstTune else {
            Issue.record("Expected a Tune despite missing K:")
            return
        }
        #expect(tune.key.mode == .major)
        #expect(tune.key.tonic?.step == .c)
    }

    @Test("Tune without X: emits missingRequiredField")
    func missingReferenceNumberEmitsDiagnostic() {
        let abc = "T:No Ref\nM:4/4\nL:1/4\nK:C\nCDEF|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .missingRequiredField }
        #expect(!errors.isEmpty)
    }

    @Test("Tune without X: still produces a Tune")
    func missingReferenceNumberProducesTune() {
        let abc = "T:No Ref\nM:4/4\nL:1/4\nK:C\nCDEF|\n"
        let result = parse(abc)
        #expect(!result.score.tunes.isEmpty)
    }

    @Test("Tune without T: is valid — no missingRequiredField emitted for title")
    func missingTitleIsValid() {
        let abc = "X:1\nM:4/4\nL:1/4\nK:C\nCDEF|\n"
        let result = parse(abc)
        // T: is "should" per spec, not "must" — no error
        let titleErrors = result.score.diagnostics.filter { $0.code == .missingRequiredField }
        #expect(titleErrors.isEmpty)
        #expect(!result.score.tunes.isEmpty)
    }

    // MARK: - Malformed field payloads

    @Test("Malformed M: payload emits malformedFieldPayload")
    func malformedMeterPayload() {
        let abc = "X:1\nT:T\nM:notameter\nL:1/4\nK:C\nC|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .malformedFieldPayload }
        #expect(!errors.isEmpty)
    }

    @Test("Malformed M: still produces a Tune (parser recovers with a default)")
    func malformedMeterStillProducesTune() {
        let abc = "X:1\nT:T\nM:notameter\nL:1/4\nK:C\nC|\n"
        let result = parse(abc)
        #expect(!result.score.tunes.isEmpty)
    }

    @Test("Malformed L: payload emits malformedFieldPayload")
    func malformedUnitLengthPayload() {
        let abc = "X:1\nT:T\nM:4/4\nL:notelength\nK:C\nC|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .malformedFieldPayload }
        #expect(!errors.isEmpty)
    }

    @Test("Malformed L: still produces a Tune")
    func malformedUnitLengthStillProducesTune() {
        let abc = "X:1\nT:T\nM:4/4\nL:notelength\nK:C\nC|\n"
        let result = parse(abc)
        #expect(!result.score.tunes.isEmpty)
    }

    @Test("Malformed K: payload emits malformedFieldPayload")
    func malformedKeyPayload() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:!!!INVALID!!!\nC|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .malformedFieldPayload }
        #expect(!errors.isEmpty)
    }

    @Test("Malformed K: still produces a Tune")
    func malformedKeyStillProducesTune() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:!!!INVALID!!!\nC|\n"
        let result = parse(abc)
        #expect(!result.score.tunes.isEmpty)
    }

    @Test("Malformed Q: payload emits malformedFieldPayload")
    func malformedTempo() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nQ:notATempo\nK:C\nC|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .malformedFieldPayload }
        #expect(!errors.isEmpty)
        #expect(!result.score.tunes.isEmpty)
    }

    // MARK: - Unknown fields

    @Test("Unknown field code emits unknownField")
    func unknownFieldEmitsDiagnostic() {
        // 'Y:' is not a defined ABC field code
        let abc = "X:1\nT:T\nM:4/4\nY:weird field\nL:1/4\nK:C\nCDEF|\n"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownField }
        #expect(!warnings.isEmpty)
    }

    @Test("Unknown field — remaining tune content still parsed")
    func unknownFieldPreservesRemainingContent() {
        let abc = "X:1\nT:T\nM:4/4\nY:weird field\nL:1/4\nK:C\nCDEF|\n"
        let result = parse(abc)
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count == 4)
    }

    // MARK: - Music body errors

    @Test("Reserved character '@' in music body emits reservedCharacter")
    func reservedCharacterEmitsDiagnostic() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nC@DEF|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .reservedCharacter }
        #expect(!errors.isEmpty)
    }

    @Test("Reserved character — surrounding notes are still parsed")
    func reservedCharacterPreservesAdjacentNotes() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nC@DEF|\n"
        let result = parse(abc)
        // C before '@' and D E F after it should all be present
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count >= 3)
    }

    @Test("Dangling tie at end of tune emits danglingTie")
    func danglingTieAtEndOfTune() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nC-|\n"
        let result = parse(abc)
        let errors = result.score.diagnostics.filter { $0.code == .danglingTie }
        #expect(!errors.isEmpty)
    }

    @Test("Dangling tie — Score still returned")
    func danglingTieScoreStillReturned() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF-|\n"
        let result = parse(abc)
        #expect(result.score.tunes.count == 1)
    }

    // MARK: - Structural recovery

    @Test("Truncated tune (header only, no K:, no music body) — Score still returned")
    func truncatedTuneHeaderOnly() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n"
        let result = parse(abc)
        // Parser always returns a Score; truncated tune yields at least one diagnostic
        let hasTuneOrDiagnostic = !result.score.tunes.isEmpty || !result.score.diagnostics.isEmpty
        #expect(hasTuneOrDiagnostic)
    }

    @Test("Middle tune missing K: — all three tunes still produced")
    func malformedMiddleTunePreservesOtherTunes() {
        let abc = """
        X:1
        T:First
        M:4/4
        L:1/4
        K:G
        GABC|

        X:2
        T:Bad
        M:4/4
        L:1/4
        CDEF|

        X:3
        T:Third
        M:4/4
        L:1/4
        K:D
        DEFG|
        """
        let result = parse(abc)
        let missing = result.score.diagnostics.filter { $0.code == .missingRequiredField }
        #expect(!missing.isEmpty)
        #expect(result.score.tunes.count == 3)
    }

    @Test("First tune valid, second tune has no header fields — first tune notes intact")
    func firstTuneIntactWhenSecondMalformed() {
        let abc = "X:1\nT:Valid\nM:4/4\nL:1/4\nK:C\nCDEF|\n\n@#$@#$\n"
        let result = parse(abc)
        guard let first = result.score.tunes.first else {
            Issue.record("Expected at least one tune")
            return
        }
        let notes = first.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count == 4)
    }

    // MARK: - Unknown directives

    @Test("Unknown %% directive emits unknownDirective")
    func unknownDirectiveEmitsDiagnostic() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%totally:unknown somevalue\nC|\n"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!warnings.isEmpty)
    }

    @Test("Unknown %% directive — tune still produced")
    func unknownDirectiveTuneStillProduced() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%totally:unknown somevalue\nC|\n"
        let result = parse(abc)
        #expect(!result.score.tunes.isEmpty)
    }

    // MARK: - ParseOptions

    @Test("maxDiagnostics=1 caps the diagnostics array")
    func maxDiagnosticsCapsOutput() {
        // Multiple issues: malformed M:, unknown field W:, missing K:
        let abc = "X:1\nT:T\nM:bad\nW:unknown\nCDEF|\n"
        let options = ParseOptions(maxDiagnostics: 1)
        let result = parse(abc, options: options)
        #expect(result.score.diagnostics.count <= 1)
    }

    @Test("maxDiagnostics=0 produces an empty diagnostics array")
    func maxDiagnosticsZeroProducesNone() {
        let abc = "X:1\nT:T\nM:bad\nW:unknown\nCDEF|\n"
        let options = ParseOptions(maxDiagnostics: 0)
        let result = parse(abc, options: options)
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("hasErrors is true when any error-severity diagnostic is present")
    func hasErrorsReflectsErrorSeverity() {
        let abc = "X:1\nT:No Key\nM:4/4\nL:1/4\nCDEF|\n"
        let result = parse(abc)
        // Missing K: is an error; hasErrors must agree
        let hasError = result.score.diagnostics.contains { $0.severity == .error }
        #expect(result.hasErrors == hasError)
    }
}
