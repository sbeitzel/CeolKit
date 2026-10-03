import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #191: `%%ceolkit:fontlist` is parsed into the model with its scope and source.
@Suite("%%ceolkit:fontlist")
struct FontListDirectiveTests {

    private func parse(_ abc: String) -> ParseResult {
        CeolKitParser().parse(abc, options: .default)
    }

    private func lists(_ abc: String) -> [(mode: FontListMode, scope: Scope, line: Int)] {
        parse(abc).score.tunes.flatMap(\.directives).compactMap { scoped in
            guard case .fontList(let mode) = scoped.directive else { return nil }
            return (mode, scoped.scope, scoped.source.line)
        }
    }

    @Test("Bare, resolved and available, in any case", arguments: [
        ("", FontListMode.resolved), (" resolved", .resolved), (" available", .available),
        (" Available", .available),
    ])
    func modes(_ argument: String, _ mode: FontListMode) {
        let found = lists("%%ceolkit:fontlist\(argument)\nX:1\nT:t\nK:C\nC|]\n")
        #expect(found.map(\.mode) == [mode])
    }

    @Test("Preamble, header and body each record the directive where it was written")
    func placement() {
        let found = lists("""
            %%ceolkit:fontlist
            X:1
            T:t
            %%ceolkit:fontlist available
            K:C
            C|
            %%ceolkit:fontlist
            D|]

            """)
        #expect(found.map(\.line) == [1, 4, 7])
        guard found.count == 3 else { return }
        if case .fileGlobal = found[0].scope {} else { Issue.record("preamble should be file-global") }
        if case .tuneGlobal = found[1].scope {} else { Issue.record("header should be tune-global") }
        if case .tuneGlobal = found[2].scope {} else { Issue.record("body should be tune-global") }
        #expect(found[1].mode == .available)
    }

    @Test("A malformed argument is a warning, and the directive is dropped")
    func malformed() {
        let result = parse("X:1\nT:t\n%%ceolkit:fontlist everything\nK:C\nC|]\n")
        #expect(lists("X:1\nT:t\n%%ceolkit:fontlist everything\nK:C\nC|]\n").isEmpty)
        let warning = result.score.diagnostics.first { $0.code == .invalidFontDirective }
        #expect(warning?.severity == .warning)
        #expect(warning?.source.line == 3)
        #expect(!result.score.diagnostics.contains { $0.code == .unknownDirective })
    }
}
