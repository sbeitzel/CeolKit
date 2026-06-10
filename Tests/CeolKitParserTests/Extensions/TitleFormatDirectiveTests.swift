import Testing
import CeolKitModel
import CeolKitParser

@Suite("%%titleformat directive")
struct TitleFormatDirectiveTests {

    // MARK: - Recognition (no unknownDirective warning)

    @Test("%%titleformat in preamble does not emit unknownDirective warning")
    func noWarningPreamble() {
        let abc = "%%titleformat T0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    @Test("%%titleformat in tune header does not emit unknownDirective warning")
    func noWarningHeader() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n%%titleformat T0\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    @Test("%%titleformat in tune body does not emit unknownDirective warning")
    func noWarningBody() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%titleformat T0\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    // MARK: - Directive value round-trips

    @Test("%%titleformat in preamble attaches titleFormat directive on first tune")
    func preamblePlacement() {
        let abc = "%%titleformat T0, R-1 C1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.first?.directives.first {
            if case .titleFormat = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .titleFormat(let fmt) = directive?.directive {
            #expect(fmt == "T0, R-1 C1")
        }
    }

    @Test("%%titleformat in tune header attaches titleFormat directive")
    func headerPlacement() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\n%%titleformat R- C1\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.first?.directives.first {
            if case .titleFormat = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .titleFormat(let fmt) = directive?.directive {
            #expect(fmt == "R- C1")
        }
    }

    @Test("%%titleformat in tune body attaches titleFormat directive")
    func bodyPlacement() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n%%titleformat T1\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.first?.directives.first {
            if case .titleFormat = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .titleFormat(let fmt) = directive?.directive {
            #expect(fmt == "T1")
        }
    }

    @Test("%%titleformat with empty value is accepted")
    func emptyValue() {
        let abc = "%%titleformat \nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
        let directive = result.score.tunes.first?.directives.first {
            if case .titleFormat = $0.directive { return true }
            return false
        }
        #expect(directive != nil)
        if case .titleFormat(let fmt) = directive?.directive {
            #expect(fmt == "")
        }
    }

    @Test("%%titleformat directive has tuneGlobal scope")
    func tuneGlobalScope() {
        let abc = "%%titleformat T0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = result.score.tunes.first?.directives.first {
            if case .titleFormat = $0.directive { return true }
            return false
        }
        guard let d = directive else {
            Issue.record("Expected titleFormat directive")
            return
        }
        if case .tuneGlobal = d.scope {
            // expected
        } else {
            Issue.record("Expected .tuneGlobal scope, got \(d.scope)")
        }
    }
}
