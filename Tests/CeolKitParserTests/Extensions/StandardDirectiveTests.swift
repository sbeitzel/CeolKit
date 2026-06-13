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

    // MARK: %%flatbeams

    @Test("%%flatbeams true attaches flatBeams(true) at tune scope")
    func flatBeamsTruePreamble() {
        let abc = "%%flatbeams true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .flatBeams = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .flatBeams(let flat) = directive?.directive {
            #expect(flat == true)
        }
    }

    @Test("%%flatbeams false attaches flatBeams(false) at tune scope")
    func flatBeamsFalsePreamble() {
        let abc = "%%flatbeams false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .flatBeams = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .flatBeams(let flat) = directive?.directive {
            #expect(flat == false)
        }
    }

    @Test("%%flatbeams does not emit unknownDirective warning")
    func flatBeamsNoUnknownWarning() {
        let abc = "%%flatbeams true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknownWarnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknownWarnings.isEmpty)
    }

    @Test("%%ceolkit:pipeformat true then %%flatbeams true emits redundantDirective info")
    func flatBeamsRedundantAfterPipeFormat() {
        let abc = "%%ceolkit:pipeformat true\n%%flatbeams true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let redundant = result.score.diagnostics.filter { $0.code == .redundantDirective }
        #expect(!redundant.isEmpty)
        #expect(redundant.first?.severity == .info)
    }

    @Test("%%ceolkit:pipeformat true then %%flatbeams false is not redundant (explicit override)")
    func flatBeamsFalseAfterPipeFormatNotRedundant() {
        let abc = "%%ceolkit:pipeformat true\n%%flatbeams false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let redundant = result.score.diagnostics.filter { $0.code == .redundantDirective }
        #expect(redundant.isEmpty)
    }

    @Test("%%flatbeams true alone emits no redundantDirective diagnostic")
    func flatBeamsNoRedundancyWithoutPipeFormat() {
        let abc = "%%flatbeams true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let redundant = result.score.diagnostics.filter { $0.code == .redundantDirective }
        #expect(redundant.isEmpty)
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

    // MARK: %%footer

    @Test("%%footer in preamble with quotes stores stripped value")
    func footerPreambleQuoted() {
        let abc = "%%footer \"        Generated: $D\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        #expect(result.score.footer == "        Generated: $D")
    }

    @Test("%%footer in preamble without quotes stores trimmed value")
    func footerPreambleUnquoted() {
        let abc = "%%footer Page $P\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        #expect(result.score.footer == "Page $P")
    }

    @Test("No %%footer directive leaves score.footer nil")
    func footerAbsent() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        #expect(result.score.footer == nil)
    }

    @Test("%%footer in tune header is accepted without unknownDirective diagnostic")
    func footerTuneHeaderNoWarning() {
        let abc = "X:1\nT:T\n%%footer \"footer text\"\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    @Test("%%footer in tune body is accepted without unknownDirective diagnostic")
    func footerTuneBodyNoWarning() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%footer \"footer text\"\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    @Test("Last %%footer wins across preamble and tune headers")
    func footerLastWins() {
        let abc = """
        %%footer "first"
        X:1
        T:Tune 1
        %%footer "second"
        M:4/4
        L:1/4
        K:C
        CDEF|

        X:2
        T:Tune 2
        %%footer "third"
        M:4/4
        L:1/4
        K:G
        GABC|
        """
        let result = parse(abc)
        #expect(result.score.footer == "third")
    }

    @Test("%%footer with \\t column separators is stored verbatim")
    func footerColumnSeparatorsVerbatim() {
        let abc = "%%footer \"left\\tcenter\\tright\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        #expect(result.score.footer == "left\\tcenter\\tright")
    }

    // MARK: %%dateformat

    @Test("%%dateformat does not emit unknownDirective warning")
    func dateFormatNoUnknownWarning() {
        let abc = "%%dateformat \"%e %B %Y %H:%M\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknownWarnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknownWarnings.isEmpty)
    }

    @Test("%%dateformat quoted value strips outer quotes")
    func dateFormatQuotedStripsQuotes() {
        let abc = "%%dateformat \"%e %B %Y %H:%M\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .dateFormat = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .dateFormat(let fmt) = directive?.directive {
            #expect(fmt == "%e %B %Y %H:%M")
        }
    }

    @Test("%%dateformat in preamble attaches dateFormat at tune scope")
    func dateFormatPreambleTuneScope() {
        let abc = "%%dateformat \"%Y-%m-%d\"\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .dateFormat = $0.directive { return true }
            return false
        }
        guard let d = directive else {
            Issue.record("Expected dateFormat directive")
            return
        }
        if case .tuneGlobal = d.scope {
            // expected
        } else {
            Issue.record("Expected .tuneGlobal scope, got \(d.scope)")
        }
    }

    @Test("%%dateformat in tune body is accepted without unknownDirective diagnostic")
    func dateFormatTuneBodyNoWarning() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%dateformat \"%Y-%m-%d\"\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    // MARK: %%straightflags

    @Test("%%straightflags true attaches straightFlags(true) at tune scope")
    func straightFlagsTruePreamble() {
        let abc = "%%straightflags true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .straightFlags = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .straightFlags(let on) = directive?.directive {
            #expect(on == true)
        }
    }

    @Test("%%straightflags false attaches straightFlags(false) at tune scope")
    func straightFlagsFalsePreamble() {
        let abc = "%%straightflags false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .straightFlags = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .straightFlags(let on) = directive?.directive {
            #expect(on == false)
        }
    }

    @Test("%%straightflags does not emit unknownDirective warning")
    func straightFlagsNoUnknownWarning() {
        let abc = "%%straightflags false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknownWarnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknownWarnings.isEmpty)
    }

    @Test("%%straightflags with invalid value emits warning and drops directive")
    func straightFlagsInvalidValueWarning() {
        let abc = "%%straightflags yes\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!warnings.isEmpty)
        let hasStraightFlags = result.score.tunes.flatMap(\.directives).contains {
            if case .straightFlags = $0.directive { return true }
            return false
        }
        #expect(!hasStraightFlags)
    }

    // MARK: %%graceslurs

    @Test("%%graceslurs true attaches graceSlurs(true) at tune scope")
    func graceSlursTruePreamble() {
        let abc = "%%graceslurs true\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .graceSlurs = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .graceSlurs(let on) = directive?.directive {
            #expect(on == true)
        }
    }

    @Test("%%graceslurs false attaches graceSlurs(false) at tune scope")
    func graceSlursFalsePreamble() {
        let abc = "%%graceslurs false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.flatMap(\.directives).first {
            if case .graceSlurs = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .graceSlurs(let on) = directive?.directive {
            #expect(on == false)
        }
    }

    @Test("%%graceslurs does not emit unknownDirective warning")
    func graceSlursNoUnknownWarning() {
        let abc = "%%graceslurs false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknownWarnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknownWarnings.isEmpty)
    }

    @Test("%%graceslurs with invalid value emits warning and drops directive")
    func graceSlursInvalidValueWarning() {
        let abc = "%%graceslurs yes\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let warnings = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!warnings.isEmpty)
        let hasGraceSlurs = result.score.tunes.flatMap(\.directives).contains {
            if case .graceSlurs = $0.directive { return true }
            return false
        }
        #expect(!hasGraceSlurs)
    }
}
