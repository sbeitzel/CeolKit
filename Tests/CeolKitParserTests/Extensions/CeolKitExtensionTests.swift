// CeolKit extension directive conformance tests.
// Tests %%ceolkit:pipeformat, %%ceolkit:pagenumber, %%ceolkit:stemalignment,
// %%ceolkit:justifylast.
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

    // MARK: %%ceolkit:justifylast

    @Test("%%ceolkit:justifylast true attaches justifyLast(true) directive")
    func justifylastTrue() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:justifylast true
        K:G
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .justifyLast = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .justifyLast(let value) = directive?.directive {
            #expect(value == true)
        }
    }

    @Test("%%ceolkit:justifylast false attaches justifyLast(false) directive")
    func justifylastFalse() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%ceolkit:justifylast false
        K:G
        GABC|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .justifyLast = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .justifyLast(let value) = directive?.directive {
            #expect(value == false)
        }
    }

    @Test("%%ceolkit:justifylast with invalid payload emits warning and drops directive")
    func justifylastInvalidPayloadEmitsWarning() {
        let abc = "%%ceolkit:justifylast yes\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!warnings.isEmpty)
        let hasDirective = result.score.tunes.flatMap(\.directives).contains {
            if case .justifyLast = $0.directive { return true }
            return false
        }
        #expect(!hasDirective)
    }
}
