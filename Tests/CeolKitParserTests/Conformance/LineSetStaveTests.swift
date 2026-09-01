// Line-sets and stave numbering — issue #102.
//
// Stave index is the unit the layout passes align on: stave *k* of one voice is stave *k* of
// every other.  A source that gives a voice no line at all in some line-set used to break
// that silently — the voice simply got no stave there, and all its later music shifted up a
// line — because the parser saw a flat stream of lines and never learned that three `V:`
// lines were one system.
//
// What this file pins down is the line-set: where one ends, what every voice records at that
// boundary, and the two shapes that must *not* change — a source written one block per voice,
// and a voice that stops before the tune does.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Line-sets and stave numbering")
struct LineSetStaveTests {

    /// Each voice's stave count, in print order.
    private func staveCounts(_ result: ParseResult) -> [Int] {
        (result.score.firstTune?.voices ?? []).map(\.staves.count)
    }

    /// The source lines each stave of `voice` drew its measures from — `[]` for a stave the
    /// voice wrote nothing in.
    private func staveLines(_ result: ParseResult, _ id: String) -> [[Int]] {
        let voice = result.score.firstTune?.voices.first { $0.id == .named(id) }
        return (voice?.staves ?? []).map { $0.measures.map(\.source.line) }
    }

    // MARK: A voice omitted from a middle line-set

    @Test("A voice with no line in a middle line-set gets an empty stave there")
    func omittedMiddleLineSetLeavesAnEmptyStave() {
        // V:2 is written for the first and third line-sets and left out of the second — the
        // natural way to write it under a plan that does not print it there.  Its last line
        // is its *third* stave, not its second.
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            V:1
            CDEF|
            V:1
            cdef|
            V:2
            GABc|
            """)
        #expect(staveCounts(result) == [3, 3])
        #expect(staveLines(result, "1") == [[7], [11], [13]])
        #expect(staveLines(result, "2") == [[9], [], [15]])
    }

    @Test("The empty stave holds no measures, and no overlays either")
    func theEmptyStaveIsEmpty() {
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            V:1
            CDEF|
            V:1
            cdef|
            V:2
            GABc|
            """)
        let staff = result.score.firstTune?.voices.last?.staves[1]
        #expect(staff?.measures.isEmpty == true)
        #expect(staff?.overlays.isEmpty == true)
    }

    @Test("Two line-sets skipped in a row are two empty staves, not one")
    func consecutiveOmissionsEachGetAStave() {
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            V:1
            CDEF|
            V:1
            CDEF|
            V:1
            cdef|
            V:2
            GABc|
            """)
        #expect(staveCounts(result) == [4, 4])
        #expect(staveLines(result, "2") == [[9], [], [], [17]])
    }

    // MARK: What must not change

    @Test("A voice that stops before the tune does ends where it stops")
    func trailingOmissionDoesNotGrowEmptyStaves() {
        // The aligner pads a short tail; the parser must not invent staves for music the
        // source never wrote, or every voice would run to the end of the longest one.
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            V:1
            CDEF|
            """)
        #expect(staveCounts(result) == [2, 1])
    }

    @Test("A source written one block per voice keeps each voice counting from its own first stave")
    func blockPerVoiceIsUnchanged() {
        // Nothing here is skipped: V:2 simply begins where V:1 finished.  Its first line is
        // stave 0, which is what makes the two blocks line up.
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            GABc|
            V:2
            cdef|
            gabc'|
            """)
        #expect(staveCounts(result) == [2, 2])
        #expect(staveLines(result, "1") == [[7], [8]])
        #expect(staveLines(result, "2") == [[10], [11]])
    }

    @Test("A single-voice tune is one stave per source line, as it always was")
    func singleVoiceIsUnchanged() {
        let result = parse("""
            X:1
            L:1/4
            K:C
            CDEF|
            GABc|
            cdef|
            """)
        #expect(staveCounts(result) == [3])
        #expect(staveLines(result, "1") == [[4], [5], [6]])
    }

    @Test("Voices written inline, one line-set to a line, still get one stave each per line")
    func inlineVoiceSwitchesAreOneLineSetPerLine() {
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            [V:1]CDEF|
            [V:2]GABc|
            [V:1]cdef|
            [V:2]gabc'|
            """)
        #expect(staveCounts(result) == [2, 2])
        #expect(staveLines(result, "1") == [[6], [8]])
        #expect(staveLines(result, "2") == [[7], [9]])
    }

    @Test("An & overlay line stays with the music it overlays rather than opening a line-set")
    func overlayContinuationDoesNotBreakTheLineSet() {
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            &GABc|
            V:2
            cdef|
            V:1
            CDEF|
            V:2
            cdef|
            """)
        #expect(staveCounts(result) == [2, 2])
        #expect(result.score.firstTune?.voices.first?.staves[0].overlays.count == 1)
    }

    // MARK: Where a line-set ends

    @Test("A %%score after a line-set governs from the stave below it")
    func bodyPlanTakesTheNextStave() {
        // The boundary belongs after the last line the previous set wrote, so the plan
        // introducing the next one is read on its own side of the break.
        let result = parse("""
            X:1
            L:1/4
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            %%score [1]
            V:1
            CDEF|
            """)
        #expect(result.score.firstTune?.staffPlans.map(\.effectiveFromStave) == [1])
    }

    @Test("A voice omitted from a middle line-set draws no diagnostic")
    func theOmissionIsNotAnError() {
        // Legal ABC, and idiomatic under a plan that does not print the voice there.
        let result = parse("""
            X:1
            L:1/4
            %%score [1 2]
            V:1
            V:2
            K:C
            V:1
            CDEF|
            V:2
            GABc|
            %%score [1]
            V:1
            CDEF|
            %%score [1 2]
            V:1
            cdef|
            V:2
            GABc|
            """)
        #expect(result.diagnostics.isEmpty)
        #expect(staveCounts(result) == [3, 3])
    }
}
