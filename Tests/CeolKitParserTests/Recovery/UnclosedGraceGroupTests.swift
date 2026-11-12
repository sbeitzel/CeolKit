// Issue #278: a grace group left open is closed with a diagnostic, not silently.
//
// `T{gef` at the end of a line used to close the group and say nothing.  abcm2ps 8.14
// reports "EOLN in grace note sequence" at the `{`.  The recovery is unchanged — the group
// is closed and its notes are kept — and a diagnostic now points at the `{`.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Unclosed grace groups")
struct UnclosedGraceGroupTests {

    private func tune(_ body: String) -> String {
        "X:1\nL:1/8\nK:D\n\(body)"
    }

    private func unclosed(_ result: ParseResult) -> [Diagnostic] {
        result.score.diagnostics.filter { $0.code == .unclosedGraceGroup }
    }

    @Test("A grace group open at the end of the line is reported at its {")
    func endOfLineReportsAtBrace() throws {
        let result = parse(tune("T{gef\ne2|]"))
        let found = unclosed(result)
        #expect(found.count == 1)
        let diagnostic = try #require(found.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.source.line == 4)
        #expect(diagnostic.source.column == 2)
    }

    @Test("The unclosed group still keeps its notes")
    func endOfLineKeepsNotes() throws {
        let result = parse(tune("T{gef\ne2|]"))
        let measure = try #require(result.score.firstTune?.singleVoiceMeasures.first)
        let grace = try #require(measure.graceEvents.first)
        #expect(grace.notes.count == 3)
    }

    @Test("An & inside the braces is reported at the {")
    func overlayReportsAtBrace() throws {
        let result = parse(tune("a2 {ge & b2|]"))
        let found = unclosed(result)
        #expect(found.count == 1)
        let diagnostic = try #require(found.first)
        #expect(diagnostic.source.line == 4)
        #expect(diagnostic.source.column == 4)
    }

    @Test("A closed grace group is not reported")
    func closedGroupIsQuiet() {
        #expect(unclosed(parse(tune("T{gef}e2|]"))).isEmpty)
    }

    @Test("Strict recovery makes an unclosed grace group an error")
    func strictIsError() throws {
        let result = parse(tune("T{gef\ne2|]"), options: ParseOptions(strictRecovery: true))
        let diagnostic = try #require(unclosed(result).first)
        #expect(diagnostic.severity == .error)
    }
}
