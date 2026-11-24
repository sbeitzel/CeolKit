//
//  BarNumberDirectiveTests.swift
//  CeolKitParserTests
//
//  Issue #290: `%%barnumbers` / `%%measurenb`, `%%measurefirst` and `%%measurebox` (ABC v2.2
//  §11.4.4), which were reported as unknown directives and dropped.
//

import Testing
import CeolKitModel
import CeolKitParser

@Suite("Bar number directives (§11.4.4)")
struct BarNumberDirectiveTests {

    private func parse(_ abc: String) -> ParseResult {
        CeolKitParser().parse(abc, options: .default)
    }

    private func tune(header line: String) -> String {
        "X:1\nT:Test\nM:4/4\nL:1/4\n\(line)\nK:G\nGABc|"
    }

    private func directives(_ abc: String) -> [(CeolKitDirective, Scope)] {
        parse(abc).score.tunes.flatMap(\.directives).compactMap { scoped in
            switch scoped.directive {
            case .barNumbers, .firstBarNumber, .measureBox: return (scoped.directive, scoped.scope)
            default:                                        return nil
            }
        }
    }

    private func barNumbers(_ abc: String) -> [Int] {
        directives(abc).compactMap { if case .barNumbers(let n) = $0.0 { return n }; return nil }
    }

    @Test("%%barnumbers and %%measurenb are the same directive",
          arguments: ["barnumbers", "measurenb"], [-1, 0, 1, 4])
    func aliases(name: String, every: Int) {
        let abc = tune(header: "%%\(name) \(every)")
        #expect(barNumbers(abc) == [every])
        #expect(!parse(abc).score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("%%barnumbers below -1, or not an integer, is dropped with a warning",
          arguments: ["-2", "four", "2.5", ""])
    func invalidBarNumbers(payload: String) {
        let abc = tune(header: "%%barnumbers \(payload)")
        #expect(barNumbers(abc).isEmpty)
        let warnings = parse(abc).score.diagnostics.filter {
            $0.code == .unknownDirective && $0.severity == .warning
        }
        #expect(warnings.count == 1)
    }

    @Test("%%measurefirst takes an integer")
    func measureFirst() {
        let values = directives(tune(header: "%%measurefirst 17")).compactMap {
            if case .firstBarNumber(let n) = $0.0 { return n }; return nil
        }
        #expect(values == [17])
        #expect(directives(tune(header: "%%measurefirst x")).isEmpty)
    }

    @Test("%%measurebox takes a logical", arguments: [("1", true), ("false", false)])
    func measureBox(payload: String, expected: Bool) {
        let values = directives(tune(header: "%%measurebox \(payload)")).compactMap {
            if case .measureBox(let on) = $0.0 { return on }; return nil
        }
        #expect(values == [expected])
    }

    @Test("Each is scoped like the other formatting directives")
    func scopes() {
        let fileHeader = "%%barnumbers 4\n\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF|\n"
        let fileScoped = directives(fileHeader)
        #expect(fileScoped.count == 1)
        if case .fileGlobal = fileScoped.first?.1 {} else {
            Issue.record("expected file scope, got \(String(describing: fileScoped.first?.1))")
        }

        let tuneHeader = directives(tune(header: "%%measurenb 2"))
        if case .tuneGlobal = tuneHeader.first?.1 {} else {
            Issue.record("expected tune scope, got \(String(describing: tuneHeader.first?.1))")
        }

        // Written in the body, it governs the whole tune, as `%%stretchstaff` does there.
        let body = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF|\n%%barnumbers 1\nGABc|\n"
        let bodyScoped = directives(body)
        #expect(bodyScoped.count == 1)
        if case .tuneGlobal = bodyScoped.first?.1 {} else {
            Issue.record("expected tune scope, got \(String(describing: bodyScoped.first?.1))")
        }
        #expect(!parse(body).score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("The I: form is the same directive")
    func instructionField() {
        #expect(barNumbers(tune(header: "I:measurenb 3")) == [3])
    }
}
