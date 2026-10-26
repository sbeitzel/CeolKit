// A last bar with no closing bar line stays on the stave the source wrote it on (#249).
//
// A source line break records a stave break while the bar after the last bar line is still
// open.  Where the source goes on writing that bar on the next line, it ends there and so
// belongs to the next stave; where it never does — the last bar of the tune — it stays put.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Open last bar and stave breaks (#249)")
struct OpenLastBarStaveTests {

    private func barsPerStave(_ body: String) -> [Int] {
        let abc = "X:1\nT:t\nM:4/4\nL:1/4\nK:C\n" + body
        let staves = parse(abc).score.tunes.first?.voices.first?.staves ?? []
        return staves.map(\.measures.count)
    }

    @Test("An unclosed last bar stays on its line")
    func unclosedLastBar() {
        #expect(barsPerStave("CDEF|GABc\n") == [2])
    }

    @Test("An unclosed last bar with no trailing newline stays on its line")
    func unclosedLastBarNoNewline() {
        #expect(barsPerStave("CDEF|GABc") == [2])
    }

    @Test("An unclosed last bar on a later line stays on that line")
    func unclosedLastBarOnSecondLine() {
        #expect(barsPerStave("CDEF|GABc|\ncBAG|FEDC\n") == [2, 2])
    }

    @Test("A closed last bar is unchanged")
    func closedLastBar() {
        #expect(barsPerStave("CDEF|GABc|\n") == [2])
    }

    @Test("A bar continued across a line break ends on the next stave")
    func barContinuedAcrossLines() {
        #expect(barsPerStave("CDEF|GA\nBc|\n") == [1, 1])
    }

    @Test("An unclosed bar continued across a line break ends on the next stave")
    func unclosedBarContinuedAcrossLines() {
        #expect(barsPerStave("CDEF|GA\nBc\n") == [1, 1])
    }

    @Test("A variant ending in an unclosed last bar stays on its line")
    func endingInUnclosedLastBar() {
        #expect(barsPerStave("|:CDEF|1GABc:|2cBAG\n") == [3])
    }
}
