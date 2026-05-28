// Standard ABC v2.2 stylesheet directive conformance tests.
// Tests %%landscape.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Standard ABC Directives")
struct StandardDirectiveTests {

    // MARK: %%landscape

    @Test("%%landscape 0 in preamble attaches landscape(false) at tune scope")
    func landscapeFalsePreamble() {
        let abc = """
        %%landscape 0
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .landscape = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == false)
        }
    }

    @Test("%%landscape 1 in preamble attaches landscape(true) at tune scope")
    func landscapeTruePreamble() {
        let abc = """
        %%landscape 1
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .landscape = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == true)
        }
    }

    @Test("%%landscape 0 in tune header attaches landscape(false)")
    func landscapeFalseHeader() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        %%landscape 0
        K:C
        CDEF|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .landscape = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == false)
        }
    }

    @Test("%%landscape 1 in tune body attaches landscape(true)")
    func landscapeTrueBody() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        %%landscape 1
        CDEF|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let directive = tune?.directives.first(where: {
            if case .landscape = $0.directive { return true }
            return false
        })
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == true)
        }
    }

    @Test("%%landscape does not emit unknownDirective warning")
    func landscapeNoWarning() {
        let abc = "%%landscape 0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknownWarnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknownWarnings.isEmpty)
    }

    @Test("%%landscape false (word) is accepted as portrait")
    func landscapeFalseWord() {
        let abc = "%%landscape false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .landscape = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == false)
        }
    }

    @Test("%%landscape true (word) is accepted as landscape")
    func landscapeTrueWord() {
        let abc = "%%landscape true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .landscape = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == true)
        }
    }

    @Test("%%landscape word forms are case-insensitive")
    func landscapeWordCaseInsensitive() {
        let abc = "%%landscape FALSE\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .landscape = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .landscape(let isLandscape) = directive?.directive {
            #expect(isLandscape == false)
        }
    }

    @Test("%%landscape with invalid value emits warning and drops directive")
    func landscapeInvalidValueWarning() {
        let abc = "%%landscape yes\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!warnings.isEmpty)
        let hasLandscape = result.score.tunes.flatMap(\.directives).contains {
            if case .landscape = $0.directive { return true }
            return false
        }
        #expect(!hasLandscape)
    }

    @Test("%%landscape directive has tuneGlobal scope")
    func landscapeScope() {
        let abc = "%%landscape 0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .landscape = $0.directive { return true }
            return false
        }
        guard let d = directive else {
            Issue.record("Expected landscape directive")
            return
        }
        if case .tuneGlobal = d.scope {
            // expected
        } else {
            Issue.record("Expected .tuneGlobal scope, got \(d.scope)")
        }
    }
}
