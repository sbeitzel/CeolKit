// Issue #86: a tuplet that ends before the notes it asked for keeps what it collected.
//
// Three ways a tuplet can be cut short — a bar line, the end of a line, and a second `(`
// opening inside it — each of which used to discard every event the tuplet had gathered,
// silently.  The contract now is the one the rest of the parser keeps: the music survives,
// and a diagnostic says what happened.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Incomplete Tuplets")
struct IncompleteTupletTests {

    private func tune(_ body: String) -> String {
        "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n\(body)"
    }

    private func incompleteWarnings(_ result: ParseResult) -> [Diagnostic] {
        result.score.diagnostics.filter { $0.code == .incompleteTuplet }
    }

    // MARK: - A bar line ends the tuplet

    @Test("A tuplet cut short by a bar line keeps its notes")
    func barLineKeepsNotes() {
        let measures = parse(tune("(3ab | cdef |\n")).score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else {
            Issue.record("Expected the truncated tuplet to survive the bar line")
            return
        }
        #expect(tuplet.events.count == 2)
    }

    @Test("A tuplet cut short by a bar line keeps p and q, and corrects r")
    func barLineCorrectsR() {
        let measures = parse(tune("(3ab | cdef |\n")).score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else {
            Issue.record("Expected the truncated tuplet to survive the bar line")
            return
        }
        #expect(tuplet.p == 3)
        #expect(tuplet.q == 2)
        #expect(tuplet.r == 2)
    }

    @Test("The notes of a truncated tuplet are still scaled by q/p")
    func truncatedTupletStillScales() {
        let measures = parse(tune("(3ab | cdef |\n")).score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first, case .note(let first) = tuplet.events.first else {
            Issue.record("Expected the truncated tuplet to survive the bar line")
            return
        }
        #expect(first.duration == Fraction(numerator: 2, denominator: 3))
    }

    @Test("A tuplet cut short by a bar line warns")
    func barLineWarns() {
        let warnings = incompleteWarnings(parse(tune("(3ab | cdef |\n")))
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
    }

    // MARK: - The end of a line ends the tuplet

    @Test("A tuplet left open at the end of a line keeps its notes, and warns")
    func endOfLineKeepsNotes() {
        let result = parse(tune("(3ab\ncdef|\n"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else {
            Issue.record("Expected the truncated tuplet to survive the line break")
            return
        }
        #expect(tuplet.events.count == 2)
        #expect(incompleteWarnings(result).count == 1)
    }

    @Test("A tuplet does not swallow the notes of the following line")
    func endOfLineDoesNotRunOn() {
        let measures = parse(tune("(3ab\ncdef|\n")).score.firstTune?.singleVoiceMeasures ?? []
        let notes = measures.last?.noteEvents ?? []
        #expect(notes.count == 4)
    }

    // MARK: - A second tuplet ends the first

    @Test("A tuplet restarted inside another keeps both sets of notes")
    func restartKeepsBothTuplets() {
        let result = parse(tune("(3ab(3cde |\n"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        #expect(tuplets.count == 2)
        #expect(tuplets.first?.events.count == 2)
        #expect(tuplets.first?.r == 2)
        #expect(tuplets.last?.events.count == 3)
        #expect(tuplets.last?.r == 3)
        #expect(incompleteWarnings(result).count == 1)
    }

    // MARK: - A tuplet with nothing after it

    @Test("A tuplet with no notes at all draws nothing and warns")
    func emptyTupletWarns() {
        let result = parse(tune("(3 | cdef |\n"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        #expect(tuplets.isEmpty)
        #expect(incompleteWarnings(result).count == 1)
    }

    // MARK: - Well-formed tuplets are untouched

    @Test("A complete tuplet is unchanged and silent")
    func completeTupletIsSilent() {
        let result = parse(tune("(3abc |\n"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        #expect(tuplets.first?.r == 3)
        #expect(tuplets.first?.events.count == 3)
        #expect(incompleteWarnings(result).isEmpty)
    }

    @Test("A space inside a tuplet breaks a beam, it does not count as one of the r notes")
    func spaceInsideTupletIsNotANote() {
        let result = parse(tune("(3a b c d2 |\n"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let tuplets = measures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else {
            Issue.record("Expected a tuplet spanning the three spaced notes")
            return
        }
        #expect(tuplet.r == 3)
        let notes = tuplet.events.compactMap { event -> Note? in
            if case .note(let n) = event { return n } else { return nil }
        }
        #expect(notes.count == 3)
        #expect(incompleteWarnings(result).isEmpty)
    }
}
