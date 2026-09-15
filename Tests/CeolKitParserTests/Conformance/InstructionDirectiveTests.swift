// `I:` fields as stylesheet directives. ABC §3.1.19, §11.0.2.
//
// "The I: field can be used interchangeably with stylesheet directives so that any
// I:directive may instead be written %%directive, and vice-versa."  In the file and tune
// headers — where `I:` fields normally go — an `I:` directive was dropped (issue #148).
import Testing
import CeolKitModel
import CeolKitParser

@Suite("I: fields as stylesheet directives (§3.1.19)")
struct InstructionDirectiveTests {

    private func unknownDirectives(_ result: ParseResult) -> [Diagnostic] {
        result.diagnostics.filter { $0.code == .unknownDirective }
    }

    @Test("I: in the file header is a file-global directive")
    func fileHeader() {
        let result = parse("I:straightflags true\n\nX:1\nT:T\nK:C\nC|\n")
        let directives = result.score.firstTune?.directives ?? []
        #expect(directives.map(\.directive) == [.straightFlags(true)])
        #expect(directives.allSatisfy { if case .fileGlobal = $0.scope { true } else { false } })
        #expect(unknownDirectives(result).isEmpty)
    }

    @Test("I: in the tune header is a tune-global directive")
    func tuneHeader() {
        let result = parse("X:1\nT:T\nI:dateformat Y-m\nK:C\nC|\n")
        let directives = result.score.firstTune?.directives ?? []
        #expect(directives.map(\.directive) == [.dateFormat("Y-m")])
        #expect(directives.allSatisfy { if case .tuneGlobal = $0.scope { true } else { false } })
        #expect(unknownDirectives(result).isEmpty)
    }

    @Test("Header I: and %% directives keep their source order")
    func interleavesWithPercentForm() {
        let iThenPercent = parse("X:1\nT:T\nI:graceslurs true\n%%graceslurs false\nK:C\nC|\n")
        #expect(iThenPercent.score.firstTune?.directives.map(\.directive)
                == [.graceSlurs(true), .graceSlurs(false)])

        let percentThenI = parse("X:1\nT:T\n%%graceslurs false\nI:graceslurs true\nK:C\nC|\n")
        #expect(percentThenI.score.firstTune?.directives.map(\.directive)
                == [.graceSlurs(false), .graceSlurs(true)])
    }

    @Test("I: in a file header with no X: still applies")
    func implicitTune() {
        let result = parse("I:straightflags true\nT:T\nK:C\nC|\n")
        #expect(result.score.firstTune?.directives.map(\.directive) == [.straightFlags(true)])
    }

    @Test("An unsupported header I: directive is reported as %% would be")
    func unknownDirective() {
        let preamble = parse("I:bogus 1\n\nX:1\nT:T\nK:C\nC|\n")
        #expect(unknownDirectives(preamble).count == 1)

        let header = parse("X:1\nT:T\nI:bogus 1\nK:C\nC|\n")
        #expect(unknownDirectives(header).count == 1)
    }

    @Test("A bare %% names no directive and is a comment, as a bare I: is ignored")
    func bareDirective() {
        let abc = "%%\nI:\n\nX:1\nT:T\n%%  \nI:\nK:C\nC|\\\n%%\nD|\n%%\nE|\n"
        let result = parse(abc)
        #expect(unknownDirectives(result).isEmpty)
        #expect(result.score.firstTune?.directives.isEmpty == true)
        #expect(result.score.firstTune?.firstVoice?.staves.count == 2)
    }

    @Test("Parser instructions in a header are not stylesheet directives")
    func parserInstructions() {
        let abc = "I:abc-charset utf-8\nI:abc-creator me\n\nX:1\nT:T\nI:linebreak $\nI:abc-version 2.2\nK:C\nC|\n"
        let result = parse(abc)
        #expect(unknownDirectives(result).isEmpty)
        #expect(result.score.firstTune?.directives.isEmpty == true)
    }

    @Test("I:footer and I:newpage in headers act as their %% forms")
    func footerAndNewPage() {
        let result = parse("I:footer \"page $P\"\n\nX:1\nT:T\nI:newpage 3\nK:C\nC|\n")
        #expect(result.score.footer == "page $P")
        #expect(result.score.firstTune?.pageBreaks.map(\.restartingAt) == [3])
    }

    @Test("A header I: keeps \\% for the directive to read")
    func headerKeepsEscape() {
        let result = parse(#"X:1\#nT:T\#nI:dateformat \%Y % remark\#nK:C\#nC|\#n"#)
        #expect(result.score.firstTune?.directives.map(\.directive) == [.dateFormat(#"\%Y"#)])
    }
}
