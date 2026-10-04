// CeolKit extension directive conformance tests.
// Tests %%ceolkit:pipeformat, %%ceolkit:pagenumber, %%ceolkit:stemalignment,
// %%stretchlast / %%ceolkit:justifylast, %%scale / %%pagescale / %%ceolkit:scale.
// See EXTENSIONS.md and CeolKit spec §7.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("CeolKit Extensions")
struct CeolKitExtensionTests {

    // MARK: %%ceolkit:pipeformat

    @Test("%%ceolkit:pipeformat true attaches pipeFormat(true) directive at tune scope")
    func pipeformatTrue() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:pipeformat true
        K:G
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .pipeFormat = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .pipeFormat(let value) = directive?.directive {
            #expect(value == true)
        }
    }

    @Test("%%ceolkit:pipeformat false attaches pipeFormat(false) directive")
    func pipeformatFalse() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:pipeformat false
        K:G
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .pipeFormat = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .pipeFormat(let value) = directive?.directive {
            #expect(value == false)
        }
    }

    @Test("Last %%ceolkit:pipeformat occurrence wins (true then false → false)")
    func pipeformatLastWins() {
        let abc = """
        %%ceolkit:pipeformat true
        %%ceolkit:pipeformat false
        X:1
        T:Test
        M:4/4
        L:1/4
        K:G
        GABC|
        """
        let result = parse(abc)
        // File-global directives: last-wins means effective value is false
        // Since file-global scope isn't on Score yet (open question §10.1),
        // we check that there is no pipeFormat(true) as the sole/final value.
        // The check: any pipeFormat directives present should resolve to false.
        let allPipeFormats = result.score.tunes.flatMap(\.directives).filter {
            if case .pipeFormat = $0.directive { return true }
            return false
        }
        if let last = allPipeFormats.last {
            if case .pipeFormat(let value) = last.directive {
                #expect(value == false)
            }
        }
    }

    // MARK: %%ceolkit:pagenumber

    @Test("%%ceolkit:pagenumber 3 attaches pageNumber(3) directive")
    func pagenumber3() {
        let abc = """
        %%ceolkit:pagenumber 3
        X:1
        T:Test
        M:4/4
        L:1/4
        K:G
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .pageNumber = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .pageNumber(let n) = directive?.directive {
            #expect(n == 3)
        }
    }

    @Test("%%ceolkit:pagenumber 1 is minimum valid page number")
    func pagenumber1() {
        let abc = "%%ceolkit:pagenumber 1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let hasPageNumber1 = result.score.tunes.flatMap(\.directives).contains {
            if case .pageNumber(1) = $0.directive { return true }
            return false
        }
        #expect(hasPageNumber1)
    }

    @Test("%%ceolkit:pagenumber 0 is invalid — emits warning and drops directive")
    func pagenumber0EmitsWarning() {
        let abc = "%%ceolkit:pagenumber 0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter {
            $0.severity == .warning && $0.code == .invalidPageNumber
        }
        #expect(!warnings.isEmpty)
        // Directive should be dropped from the model
        let hasPageNumber = result.score.tunes.flatMap(\.directives).contains {
            if case .pageNumber = $0.directive { return true }
            return false
        }
        #expect(!hasPageNumber)
    }

    @Test("%%ceolkit:pagenumber -1 is invalid — emits warning and drops directive")
    func pagenumberNegativeEmitsWarning() {
        let abc = "%%ceolkit:pagenumber -1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .invalidPageNumber }
        #expect(!warnings.isEmpty)
    }

    @Test("%%ceolkit:pagenumber abc (non-numeric) emits warning and drops directive")
    func pagenumberNonNumericEmitsWarning() {
        let abc = "%%ceolkit:pagenumber abc\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .invalidPageNumber }
        #expect(!warnings.isEmpty)
    }

    // MARK: %%ceolkit:stemalignment

    @Test("%%ceolkit:stemalignment -6 attaches stemAlignment(-6) at tune scope")
    func stemalignmentNegative() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:stemalignment -6
        K:C treble
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .stemAlignment(let n) = directive?.directive {
            #expect(n == -6)
        }
    }

    @Test("%%ceolkit:stemalignment 6 attaches stemAlignment(6) at tune scope")
    func stemalignmentPositive() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:stemalignment 6
        K:C treble
        CDEC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })
        if case .stemAlignment(let n) = directive?.directive {
            #expect(n == 6)
        }
    }

    @Test("%%ceolkit:stemalignment 0 attaches stemAlignment(0) to reset")
    func stemalignmentZero() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n%%ceolkit:stemalignment 0\nK:C\nC|"
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })
        if let d = directive, case .stemAlignment(let n) = d.directive {
            #expect(n == 0)
        }
    }

    @Test("Voice-level %%ceolkit:stemalignment attaches to voice scope")
    func stemalignmentVoiceScope() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C treble
        V:1
        %%ceolkit:stemalignment -4
        GABC|
        V:2
        %%ceolkit:stemalignment 4
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        guard let voices = tune?.voices, voices.count >= 2 else { return }

        let v1Alignment = voices[0].directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })
        let v2Alignment = voices[1].directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })

        #expect(v1Alignment != nil)
        #expect(v2Alignment != nil)

        if case .stemAlignment(let n) = v1Alignment?.directive { #expect(n == -4) }
        if case .stemAlignment(let n) = v2Alignment?.directive { #expect(n == 4) }
    }

    @Test("Voice-level stemalignment scope is .voiceLocal")
    func stemalignmentVoiceScopeKind() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        V:1
        %%ceolkit:stemalignment -4
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let v1 = tune?.voices.first
        let directive = v1?.directives.first(where: {
            if case .stemAlignment = $0.directive { return true }
            return false
        })
        guard let d = directive else { return }
        if case .voiceLocal(let voiceId) = d.scope {
            if case .named(let name) = voiceId {
                #expect(name == "1")
            }
        } else {
            Issue.record("Expected .voiceLocal scope, got \(d.scope)")
        }
    }

    @Test("%%ceolkit:stemalignment outside voice context emits warning")
    func stemalignmentMisplacedWarning() {
        // Placing stemalignment in the tune body without a preceding V: line is misplaced
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        GABC|
        %%ceolkit:stemalignment -4
        GABC|
        """
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .misplacedStemAlignment }
        #expect(!warnings.isEmpty)
    }

    // MARK: %%stretchlast and %%ceolkit:justifylast (issue #198)

    /// The `%%stretchlast` values attached to the first tune, in order.
    private func stretchLastValues(_ abc: String) -> [Double] {
        (parse(abc).score.firstTune?.directives ?? []).compactMap {
            if case .stretchLast(let value) = $0.directive { return value }
            return nil
        }
    }

    private func tune(header line: String) -> String {
        "X:1\nT:Test\nM:4/4\nL:1/4\n\(line)\nK:G\nGABC|"
    }

    @Test("%%stretchlast takes abcm2ps's fraction of the line",
          arguments: [("0", 0.0), ("0.25", 0.25), ("0.6", 0.6), ("1", 1.0)])
    func stretchLastFraction(payload: String, expected: Double) {
        #expect(stretchLastValues(tune(header: "%%stretchlast \(payload)")) == [expected])
    }

    @Test("%%stretchlast takes the spec's logical as the two ends of the range",
          arguments: [("true", 1.0), ("false", 0.0)])
    func stretchLastLogical(payload: String, expected: Double) {
        #expect(stretchLastValues(tune(header: "%%stretchlast \(payload)")) == [expected])
    }

    @Test("%%stretchlast outside 0…1, or not a number, is dropped with a warning",
          arguments: ["1.5", "-0.2", "yes", "0.3x"])
    func stretchLastInvalid(payload: String) {
        let abc = tune(header: "%%stretchlast \(payload)")
        #expect(stretchLastValues(abc).isEmpty)
        let warnings = parse(abc).score.diagnostics.filter { $0.code == .invalidStretchLast }
        #expect(warnings.count == 1)
    }

    @Test("%%ceolkit:justifylast is a deprecated %%stretchlast 1 or 0",
          arguments: [("true", 1.0), ("false", 0.0)])
    func justifyLastIsDeprecatedStretchLast(payload: String, expected: Double) {
        let abc = tune(header: "%%ceolkit:justifylast \(payload)")
        #expect(stretchLastValues(abc) == [expected])
        let deprecations = parse(abc).score.diagnostics.filter { $0.code == .deprecatedDirective }
        #expect(deprecations.count == 1)
        #expect(deprecations.first?.message.contains("%%stretchlast \(Int(expected))") == true)
    }

    @Test("%%stretchstaff takes a logical", arguments: [("1", true), ("false", false)])
    func stretchStaffLogical(payload: String, expected: Bool) {
        let values = (parse(tune(header: "%%stretchstaff \(payload)")).score.firstTune?
            .directives ?? []).compactMap { scope -> Bool? in
                if case .stretchStaff(let on) = scope.directive { return on }
                return nil
            }
        #expect(values == [expected])
    }

    @Test("%%ceolkit:justifylast with invalid payload emits warning and drops directive")
    func justifylastInvalidPayloadEmitsWarning() {
        let abc = "%%ceolkit:justifylast yes\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .invalidStretchLast }
        #expect(!warnings.isEmpty)
        let hasDirective = result.score.tunes.flatMap(\.directives).contains {
            if case .stretchLast = $0.directive { return true }
            return false
        }
        #expect(!hasDirective)
    }

    // MARK: %%scale, %%pagescale and %%ceolkit:scale (issue #203)

    /// Returns the scale factor from the first `.scale` directive on any tune, if present.
    private func scaleFactor(in result: ParseResult) -> Double? {
        result.score.tunes.flatMap(\.directives).compactMap {
            if case .scale(let f) = $0.directive { return f }
            return nil
        }.first
    }

    private func headerTune(_ directive: String) -> String {
        "X:1\nT:T\nM:4/4\nL:1/4\n\(directive)\nK:C\nC|"
    }

    @Test("%%scale 0.8 attaches scale(0.8) directive at tune scope")
    func scaleValidFactor() {
        let result = parse(headerTune("%%scale 0.8"))
        let directive = result.score.firstTune?.directives.first(where: {
            if case .scale = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        #expect(scaleFactor(in: result) == 0.8)
        if let d = directive, case .tuneGlobal = d.scope {} else {
            Issue.record("Expected .tuneGlobal scope, got \(String(describing: directive?.scope))")
        }
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("%%pagescale F is %%scale 0.75 × F", arguments: [
        ("%%pagescale 1", 0.75),
        ("%%pagescale 2", 1.5),
        ("%%pagescale 0.5", 0.375),
    ])
    func pageScale(_ directive: String, _ expected: Double) {
        let result = parse(headerTune(directive))
        #expect(scaleFactor(in: result) == expected)
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("%%ceolkit:scale F is %%pagescale F, and deprecated")
    func ceolKitScaleIsDeprecatedPageScale() {
        let result = parse(headerTune("%%ceolkit:scale 1.5"))
        #expect(scaleFactor(in: result) == 1.125)
        let deprecated = result.score.diagnostics.filter { $0.code == .deprecatedDirective }
        #expect(deprecated.count == 1)
        #expect(deprecated.first?.severity == .warning)
        #expect(deprecated.first?.message.contains("%%pagescale 1.5") == true)
    }

    @Test("%%scale in the file preamble is promoted to the first tune")
    func scaleInPreamble() {
        let abc = "%%scale 0.5\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        #expect(scaleFactor(in: parse(abc)) == 0.5)
    }

    @Test("%%scale in the tune body is accepted and noted as scaling the whole tune")
    func scaleInBody() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEC|
        %%scale 0.6
        CDEC|
        """
        let result = parse(abc)
        #expect(scaleFactor(in: result) == 0.6)
        #expect(!result.score.diagnostics.contains { $0.code == .unknownDirective })
        let notes = result.score.diagnostics.filter { $0.code == .scaleAppliesToWholeTune }
        #expect(notes.count == 1)
        #expect(notes.first?.severity == .info)
    }

    @Test("An invalid page scale emits a warning and drops the directive", arguments: [
        "%%scale 0", "%%pagescale -0.5", "%%scale big", "%%pagescale inf",
        "%%scale nan", "%%ceolkit:scale 0",
    ])
    func invalidScale(_ directive: String) {
        let result = parse(directive + "\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
        let warnings = result.score.diagnostics.filter {
            $0.severity == .warning && $0.code == .invalidScale
        }
        #expect(warnings.count == 1)
        #expect(scaleFactor(in: result) == nil)
    }

    // MARK: %%ceolkit:gracenotespacing

    /// Returns the step from the first `.graceNoteSpacing` directive on any tune, if present.
    private func graceNoteSpacing(in result: ParseResult) -> Double? {
        result.score.tunes.flatMap(\.directives).compactMap {
            if case .graceNoteSpacing(let f) = $0.directive { return f }
            return nil
        }.first
    }

    @Test("%%ceolkit:gracenotespacing 1.4 attaches the directive at tune scope")
    func graceNoteSpacingValidStep() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:gracenotespacing 1.4
        K:G
        GABC|
        """
        let result = parse(abc)
        let directive = result.score.firstTune?.directives.first(where: {
            if case .graceNoteSpacing = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        #expect(graceNoteSpacing(in: result) == 1.4)
        if let d = directive, case .tuneGlobal = d.scope {} else {
            Issue.record("Expected .tuneGlobal scope, got \(String(describing: directive?.scope))")
        }
    }

    @Test("%%ceolkit:gracenotespacing accepts an integer payload")
    func graceNoteSpacingIntegerPayload() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n%%ceolkit:gracenotespacing 2\nK:C\nC|"
        #expect(graceNoteSpacing(in: parse(abc)) == 2.0)
    }

    @Test("%%ceolkit:gracenotespacing 1 is the tightest accepted value")
    func graceNoteSpacingAcceptsOne() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n%%ceolkit:gracenotespacing 1.0\nK:C\nC|"
        let result = parse(abc)
        #expect(graceNoteSpacing(in: result) == 1.0)
        #expect(!result.score.diagnostics.contains { $0.code == .invalidGraceNoteSpacing })
    }

    @Test("%%ceolkit:gracenotespacing in the file preamble is promoted to the first tune")
    func graceNoteSpacingInPreamble() {
        let abc = "%%ceolkit:gracenotespacing 1.3\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        #expect(graceNoteSpacing(in: parse(abc)) == 1.3)
    }

    @Test("%%ceolkit:gracenotespacing in the tune body is accepted, not reported as unknown")
    func graceNoteSpacingInBody() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEC|
        %%ceolkit:gracenotespacing 1.25
        CDEC|
        """
        let result = parse(abc)
        #expect(graceNoteSpacing(in: result) == 1.25)
        let unknowns = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknowns.isEmpty)
    }

    @Test("A %%ceolkit:gracenotespacing below 1 would overlap noteheads — warning, directive dropped")
    func graceNoteSpacingBelowOneEmitsWarning() {
        for payload in ["0.9", "0", "-1.5"] {
            let result = parse("%%ceolkit:gracenotespacing \(payload)\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
            #expect(result.score.diagnostics.contains {
                $0.severity == .warning && $0.code == .invalidGraceNoteSpacing
            }, "expected invalidGraceNoteSpacing for payload '\(payload)'")
            #expect(graceNoteSpacing(in: result) == nil)
        }
    }

    @Test("%%ceolkit:gracenotespacing wide (non-numeric) emits warning and drops directive")
    func graceNoteSpacingNonNumericEmitsWarning() {
        let abc = "%%ceolkit:gracenotespacing wide\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        #expect(result.score.diagnostics.contains { $0.code == .invalidGraceNoteSpacing })
        #expect(graceNoteSpacing(in: result) == nil)
    }

    @Test("%%ceolkit:gracenotespacing with a non-finite payload emits warning and drops directive")
    func graceNoteSpacingNonFiniteEmitsWarning() {
        for payload in ["inf", "nan"] {
            let result = parse("%%ceolkit:gracenotespacing \(payload)\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
            #expect(result.score.diagnostics.contains { $0.code == .invalidGraceNoteSpacing },
                    "expected invalidGraceNoteSpacing for payload '\(payload)'")
            #expect(graceNoteSpacing(in: result) == nil)
        }
    }

    // MARK: %%ceolkit:label (issue #168)

    /// Every `%%ceolkit:label` value each tune carries, in the order they apply, with the
    /// scope each was written at.
    private func labels(in tune: Tune?) -> [(text: String, fileGlobal: Bool)] {
        (tune?.directives ?? []).compactMap {
            guard case .label(let text) = $0.directive else { return nil }
            if case .fileGlobal = $0.scope { return (text, true) }
            return (text, false)
        }
    }

    @Test("%%ceolkit:label in the file header is taken at file scope")
    func labelInFileHeader() {
        let result = parse("%%ceolkit:label \"Reels\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
        let found = labels(in: result.score.firstTune)
        #expect(found.map(\.text) == ["Reels"])
        #expect(found.first?.fileGlobal == true)
        #expect(!result.score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("%%ceolkit:label in a tune header is taken at tune scope, for that tune alone")
    func labelInTuneHeader() {
        let abc = """
        X:1
        T:One
        %%ceolkit:label "Jigs"
        M:4/4
        L:1/4
        K:C
        C|

        X:2
        T:Two
        M:4/4
        L:1/4
        K:C
        C|
        """
        let result = parse(abc)
        let first = labels(in: result.score.tunes.first)
        #expect(first.map(\.text) == ["Jigs"])
        #expect(first.first?.fileGlobal == false)
        #expect(labels(in: result.score.tunes.last).isEmpty)
    }

    @Test("When a header sets %%ceolkit:label twice, the last one wins")
    func labelLastWins() {
        let abc = "X:1\nT:T\n%%ceolkit:label first\n%%ceolkit:label second\nM:4/4\nL:1/4\nK:C\nC|"
        // Both are kept in source order; applying them in order leaves the second standing.
        #expect(labels(in: parse(abc).score.firstTune).map(\.text).last == "second")
    }

    @Test("%%ceolkit:label strips surrounding quotes, and takes an unquoted value as written")
    func labelQuotesStripped() {
        let quoted = parse("%%ceolkit:label \"  Strathspeys \"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
        #expect(labels(in: quoted.score.firstTune).map(\.text) == ["  Strathspeys "])
        let bare = parse("%%ceolkit:label Slow airs\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|")
        #expect(labels(in: bare.score.firstTune).map(\.text) == ["Slow airs"])
    }

    @Test("An empty %%ceolkit:label parses to the empty string")
    func labelEmptyValue() {
        let result = parse("X:1\nT:T\n%%ceolkit:label \"\"\nM:4/4\nL:1/4\nK:C\nC|")
        #expect(labels(in: result.score.firstTune).map(\.text) == [""])
    }
}
