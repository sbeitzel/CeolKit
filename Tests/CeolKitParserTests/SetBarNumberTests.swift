//
//  SetBarNumberTests.swift
//  CeolKitParserTests
//
//  Issue #296: `%%setbarnb N` (ABC v2.2 §11.4.4) numbers the bar it opens.  In a header it is
//  `%%measurefirst N`; in the body it is a mark on a measure, `Measure.barNumber`.
//

import Testing
import CeolKitModel
import CeolKitParser

@Suite("%%setbarnb (§11.4.4)")
struct SetBarNumberTests {

    private func parse(_ abc: String) -> ParseResult {
        CeolKitParser().parse(abc, options: .default)
    }

    private func tune(_ body: String, header: String = "") -> String {
        "X:1\nT:Test\nM:6/8\nL:1/8\n\(header)K:C\n\(body)\n"
    }

    /// Each measure's `barNumber`, in order.
    private func barNumbers(_ abc: String) -> [Int?] {
        (parse(abc).score.firstTune?.singleVoiceMeasures ?? []).map(\.barNumber)
    }

    private func firstBarNumbers(_ abc: String) -> [Int] {
        parse(abc).score.tunes.flatMap(\.directives).compactMap {
            if case .firstBarNumber(let n) = $0.directive { return n }; return nil
        }
    }

    // MARK: - Headers

    @Test("In the file header it is %%measurefirst")
    func fileHeader() {
        let abc = "%%setbarnb 7\n\n" + tune("abc cab|abc cab|")
        let scoped = parse(abc).score.tunes.flatMap(\.directives).first {
            if case .firstBarNumber = $0.directive { return true }; return false
        }
        #expect(scoped?.directive == .firstBarNumber(7))
        if case .fileGlobal = scoped?.scope {} else {
            Issue.record("expected file scope, got \(String(describing: scoped?.scope))")
        }
        #expect(barNumbers(abc) == [nil, nil])
        #expect(!parse(abc).score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("In the tune header it is %%measurefirst", arguments: ["%%setbarnb 7", "I:setbarnb 7"])
    func tuneHeader(line: String) {
        let abc = tune("abc cab|abc cab|", header: line + "\n")
        #expect(firstBarNumbers(abc) == [7])
        #expect(barNumbers(abc) == [nil, nil])
    }

    @Test("A payload that is not an integer is dropped with a warning",
          arguments: ["", "ten", "2.5"])
    func invalid(payload: String) {
        for abc in [tune("abc cab|", header: "%%setbarnb \(payload)\n"),
                    tune("abc cab|\n%%setbarnb \(payload)\nabc cab|")] {
            #expect(firstBarNumbers(abc).isEmpty)
            #expect(barNumbers(abc).allSatisfy { $0 == nil })
            let warnings = parse(abc).score.diagnostics.filter {
                $0.code == .unknownDirective && $0.severity == .warning
            }
            #expect(warnings.count == 1)
        }
    }

    // MARK: - The body

    /// §6.1.1's example: the 9/8 bar the directive opens is bar 10.  abcm2ps 8.14 would give
    /// 10 to the bar after it; CeolKit follows the spec.
    @Test("§6.1.1: on its own line after a line continuation")
    func afterContinuation() {
        let abc = tune("abc cab|\\\n%%setbarnb 10\nM:9/8\n%comment\nabc cba abc|abc cba abc|")
        #expect(barNumbers(abc) == [nil, 10, nil])
        #expect(!parse(abc).score.diagnostics.contains { $0.code == .unknownDirective })
    }

    @Test("§6.1.1: as an inline [I:setbarnb]")
    func inline() {
        let abc = tune("abc cab|[I:setbarnb 10][M:9/8][r:comment]abc cba abc|abc cba abc|")
        #expect(barNumbers(abc) == [nil, 10, nil])
    }

    @Test("§11: CDEFG|[I:setbarnb 10]ABc numbers the bar it opens")
    func specSection11() {
        #expect(barNumbers(tune("CDE FG|[I:setbarnb 10]ABc|def|")) == [nil, 10, nil])
    }

    @Test("On its own line between two lines of music")
    func ownLine() {
        #expect(barNumbers(tune("abc cab|\n%%setbarnb 3\nabc cab|abc cab|")) == [nil, 3, nil])
    }

    @Test("Before the first note it numbers the first bar")
    func firstBar() {
        #expect(barNumbers(tune("[I:setbarnb 5]abc cab|abc cab|")) == [5, nil])
    }

    @Test("Part way through a bar it numbers the next one")
    func midBar() {
        #expect(barNumbers(tune("abc [I:setbarnb 4]cab|abc cab|abc cab|")) == [nil, 4, nil])
    }

    @Test("Part way through the last bar it numbers nothing")
    func midLastBar() {
        #expect(barNumbers(tune("abc cab|abc [I:setbarnb 4]cab|")) == [nil, nil])
    }

    @Test("Against the final bar line, it numbers the unterminated bar after it")
    func lastOpenBar() {
        #expect(barNumbers(tune("abc cab|[I:setbarnb 9]abc cab")) == [nil, 9])
    }

    @Test("It numbers a bar that opens a variant ending")
    func variantEnding() {
        let abc = tune("|:abc cab|1 abc cab:|\n%%setbarnb 20\n[2 cba cba|]")
        #expect(barNumbers(abc) == [nil, nil, 20])
    }

    @Test("It numbers a multi-measure rest")
    func multiMeasureRest() {
        #expect(barNumbers(tune("abc cab|[I:setbarnb 8]Z4|abc cab|")) == [nil, 8, nil])
    }

    @Test("It belongs to the voice it is written in")
    func voices() {
        let abc = "X:1\nT:T\nM:6/8\nL:1/8\nK:C\nV:1\nabc cab|abc cab|\nV:2\nabc cab|[I:setbarnb 6]abc cab|\n"
        let tune = parse(abc).score.firstTune
        #expect(tune?.voices.map { $0.allMeasures.map(\.barNumber) } == [[nil, nil], [nil, 6]])
    }
}
