import Testing
import CeolKitModel
import CeolKitParser

@Suite("%%writefields directive")
struct WriteFieldsDirectiveTests {

    // MARK: - Recognition

    @Test("%%writefields in preamble does not emit unknownDirective warning")
    func noWarningPreamble() {
        let abc = "%%writefields TCOPQwW\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(unknown.isEmpty)
    }

    @Test("%%titleformat now emits unknownDirective info diagnostic")
    func titleFormatIsUnknown() {
        let abc = "%%titleformat T0\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let unknown = result.score.diagnostics.filter { $0.code == .unknownDirective }
        #expect(!unknown.isEmpty)
    }

    // MARK: - Parsing: field list with implicit true

    @Test("%%writefields TCOPQwW parses to writeFields(\"TCOPQwW\", true)")
    func defaultFieldListTrue() {
        let abc = "%%writefields TCOPQwW\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = firstWriteFields(in: result.score)
        guard case .writeFields(let fields, let enabled) = directive?.directive else {
            Issue.record("Expected .writeFields directive"); return
        }
        #expect(fields == "TCOPQwW")
        #expect(enabled == true)
    }

    @Test("%%writefields X (no bool) parses to writeFields(\"X\", true)")
    func singleFieldNoBool() {
        let abc = "%%writefields X\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = firstWriteFields(in: result.score)
        guard case .writeFields(let fields, let enabled) = directive?.directive else {
            Issue.record("Expected .writeFields directive"); return
        }
        #expect(fields == "X")
        #expect(enabled == true)
    }

    // MARK: - Parsing: explicit false

    @Test("%%writefields O false parses to writeFields(\"O\", false)")
    func singleFieldFalse() {
        let abc = "%%writefields O false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = firstWriteFields(in: result.score)
        guard case .writeFields(let fields, let enabled) = directive?.directive else {
            Issue.record("Expected .writeFields directive"); return
        }
        #expect(fields == "O")
        #expect(enabled == false)
    }

    @Test("%%writefields Ww false parses to writeFields(\"Ww\", false)")
    func multipleFieldsFalse() {
        let abc = "%%writefields Ww false\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        let directive = firstWriteFields(in: result.score)
        guard case .writeFields(let fields, let enabled) = directive?.directive else {
            Issue.record("Expected .writeFields directive"); return
        }
        #expect(fields == "Ww")
        #expect(enabled == false)
    }

    // MARK: - Scope

    @Test("%%writefields in file preamble has fileGlobal scope")
    func preambleIsFileGlobal() {
        let abc = "%%writefields R\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        guard let d = firstWriteFields(in: result.score) else {
            Issue.record("Expected writeFields directive"); return
        }
        if case .fileGlobal = d.scope {
            // expected
        } else {
            Issue.record("Expected .fileGlobal scope for preamble directive, got \(d.scope)")
        }
    }

    @Test("%%writefields in tune header has tuneGlobal scope")
    func tuneHeaderIsTuneGlobal() {
        let abc = "X:1\nT:T\n%%writefields R\nM:4/4\nL:1/4\nK:C\nC|"
        let result = parse(abc)
        guard let d = firstWriteFields(in: result.score) else {
            Issue.record("Expected writeFields directive"); return
        }
        if case .tuneGlobal = d.scope {
            // expected
        } else {
            Issue.record("Expected .tuneGlobal scope for tune-header directive, got \(d.scope)")
        }
    }

    // MARK: - Helpers

    private func firstWriteFields(in score: Score) -> CeolKitDirectiveScope? {
        score.tunes.first?.directives.first {
            if case .writeFields = $0.directive { return true }
            return false
        }
    }
}
