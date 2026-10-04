import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #186: the §11.4.2 font directives are parsed into the model with their scope.
@Suite("Font directives (§11.4.2)")
struct FontDirectiveTests {

    private func parse(_ abc: String) -> ParseResult {
        CeolKitParser().parse(abc, options: .default)
    }

    private func fonts(_ abc: String, tune: Int = 0) -> [(TextFontRole, FontSpec, Scope)] {
        parse(abc).score.tunes[tune].directives.compactMap { scoped in
            guard case .font(let role, let spec) = scoped.directive else { return nil }
            return (role, spec, scoped.scope)
        }
    }

    @Test("Every directive in the §11.4.2 table is recognised", arguments: TextFontRole.allCases)
    func everyRole(_ role: TextFontRole) {
        let result = parse("%%\(role.rawValue) Times-Bold 14\nX:1\nT:t\nK:C\nC|]\n")
        let found = fonts("%%\(role.rawValue) Times-Bold 14\nX:1\nT:t\nK:C\nC|]\n")
        #expect(found.count == 1)
        #expect(found.first?.0 == role)
        #expect(found.first?.1 == FontSpec(name: "Times-Bold", size: 14))
        #expect(!result.score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("A file-header directive is file-global, a tune-header one tune-global")
    func scopes() {
        let found = fonts("%%wordsfont Courier-Bold 16\nX:1\nT:t\n%%gchordfont Helvetica\nK:C\nC|]\n")
        #expect(found.map(\.0) == [.words, .chordSymbol])
        guard found.count == 2 else { return }
        if case .fileGlobal = found[0].2 {} else { Issue.record("wordsfont should be file-global") }
        if case .tuneGlobal = found[1].2 {} else { Issue.record("gchordfont should be tune-global") }
        #expect(found[1].1 == FontSpec(name: "Helvetica", size: nil))
    }

    @Test("A body directive applies to its tune")
    func bodyDirective() {
        let found = fonts("X:1\nT:t\nK:C\nC|\n%%vocalfont * 14\nD|]\n")
        #expect(found.count == 1)
        #expect(found.first?.1 == FontSpec(name: nil, size: 14))
    }

    @Test("Quoted names, * and fractional sizes")
    func payloadForms() {
        let found = fonts("""
        %%titlefont "Times New Roman" 20
        %%composerfont * 13.5
        X:1
        T:t
        K:C
        C|]

        """)
        #expect(found.map(\.1) == [FontSpec(name: "Times New Roman", size: 20),
                                   FontSpec(name: nil, size: 13.5)])
    }

    @Test("Malformed payloads are reported and dropped",
          arguments: ["", "Times-Roman big", "Times-Roman 0", "Times-Roman 12 box", "\"Times 12"])
    func malformed(_ payload: String) {
        let result = parse("%%titlefont \(payload)\nX:1\nT:t\nK:C\nC|]\n")
        #expect(result.score.diagnostics.contains { $0.code == .invalidFontDirective })
        #expect(fonts("%%titlefont \(payload)\nX:1\nT:t\nK:C\nC|]\n").isEmpty)
    }

    @Test("FontSpec layers over the spec in force half by half")
    func overriding() {
        let base = FontSpec(name: "Times-Roman", size: 12)
        #expect(FontSpec(name: nil, size: 14).overriding(base) == FontSpec(name: "Times-Roman", size: 14))
        #expect(FontSpec(name: "Courier", size: nil).overriding(base) == FontSpec(name: "Courier", size: 12))
        #expect(FontSpec(name: "Courier").overriding(nil) == FontSpec(name: "Courier", size: nil))
    }
}
