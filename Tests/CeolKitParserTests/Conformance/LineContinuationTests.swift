// Backslash continuation of music code lines. ABC §2.2 and §6.1.1.
import Testing
import CeolKitModel
import CeolKitParser

private func contTune(_ body: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(body)"
}

/// §2.2: "The backslash effectively acts as a continuation character for music code lines
/// … In particular it can continue music code lines through information fields, comments
/// and stylesheet directives."
///
/// The lines it reaches through are not part of the music.  They used to be pasted into it
/// verbatim, which turned a `w:` lyric line into a bar's worth of invented notes — §14.4
/// Canzonetta is written this way and came out with a system of nonsense.
@Suite("Line continuation (§2.2)")
struct LineContinuationTests {

    private func staves(_ body: String) -> [Staff] {
        parse(contTune(body)).score.firstTune?.firstVoice?.staves ?? []
    }

    @Test("A trailing backslash joins the next music line into the same stave")
    func backslashJoinsTwoMusicLines() {
        let joined = staves("CDEF|\\\nGABC|")
        #expect(joined.count == 1)
        #expect(joined.first?.measures.count == 2)
        // …and without it, two staves, which is what makes the score line-break.
        #expect(staves("CDEF|\nGABC|").count == 2)
    }

    @Test("The continuation reaches through a w: lyric line")
    func continuationReachesThroughLyrics() {
        let result = parse(contTune("CDEF|\\\nw: la la la la\nGABC|"))
        #expect(result.score.warningDiagnostics.isEmpty,
                "Unexpected: \(result.score.warningDiagnostics.map(\.message))")
        let staves = result.score.firstTune?.firstVoice?.staves ?? []
        #expect(staves.count == 1)
        #expect(staves.first?.measures.count == 2)
        // The lyric lands on the line it was written under, not on invented notes.
        let notes = staves.flatMap(\.measures).flatMap(\.noteEvents)
        #expect(notes.count == 8)
        #expect(notes.prefix(4).allSatisfy { $0.lyric != nil })
    }

    @Test("The continuation reaches through comments and stylesheet directives")
    func continuationReachesThroughCommentsAndDirectives() {
        // §2.2's own example, transposed to 4/4 so the meter change is visible.
        let result = parse(contTune("CDEF|\\\n%%pagenumber 3\n%a comment\nGABC|"))
        #expect(result.score.warningDiagnostics.isEmpty,
                "Unexpected: \(result.score.warningDiagnostics.map(\.message))")
        let staves = result.score.firstTune?.firstVoice?.staves ?? []
        #expect(staves.count == 1)
        #expect(staves.first?.measures.count == 2)
    }

    /// §6.1.1: "any information fields and stylesheet directives are processed (and comments
    /// are removed) at the point where the physical line-break occurs.  Hence the backslash
    /// is commonly used to include meter or key changes halfway through a line of music."
    ///
    /// A field written between the two halves therefore governs the second half, not the
    /// line after the joined one, and the standard gives the equivalence itself: it is the
    /// inline `[M:9/8]` written at the break.
    @Test("A meter change between the halves governs the second half")
    func meterChangeAtTheBreakGovernsSecondHalf() {
        // §6.1.1's own example.
        let result = parse("X:1\nT:Test\nM:4/4\nL:1/8\nK:C\nabc cab|\\\n%%setbarnb 10\nM:9/8\n%comment\nabc cba abc|\n")
        let measures = result.score.firstTune?.firstVoice?.staves.first?.measures ?? []
        #expect(measures.count == 2)
        #expect(measures.first?.meter == nil, "the first half stays in the header's 4/4")
        if case .fraction(let num, let den) = measures.last?.meter {
            #expect((num, den) == (9, 8))
        } else {
            Issue.record("second half is not in 9/8: \(String(describing: measures.last?.meter))")
        }
    }

    @Test("A key change between the halves governs the second half")
    func keyChangeAtTheBreakGovernsSecondHalf() {
        // In C the f is natural; from the break on, G major sharpens it.
        let result = parse(contTune("CDEF|\\\nK:G\nFGAB|"))
        let notes = (result.score.firstTune?.firstVoice?.staves.first?.measures ?? [])
            .map { $0.noteEvents.first?.pitch.alteration }
        #expect(notes == [.natural, .sharp])
    }

    @Test("A field with no inline form is still applied after the joined line")
    func fieldWithoutInlineFormStaysDeferred() {
        // `w:` has no inline form (§4.19), so it keeps the deferral that puts it on the
        // joined line as a whole rather than being spliced into the middle of it.
        let result = parse(contTune("CDEF|\\\nw: la la la la\nGABC|"))
        let notes = (result.score.firstTune?.firstVoice?.staves.first?.measures ?? [])
            .flatMap(\.noteEvents)
        #expect(notes.count == 8)
        #expect(notes.prefix(4).allSatisfy { $0.lyric != nil })
        #expect(notes.dropFirst(4).allSatisfy { $0.lyric == nil })
    }

    @Test("A backslash before an empty line still yields its music")
    func danglingBackslashBeforeEmptyLine() {
        // Illegal per §6.1.1, so this is the recovery path: the half-line already written
        // becomes a stave of its own rather than swallowing the rest of the file.
        let joined = staves("CDEF|\\\n\nGABC|")
        #expect(joined.first?.measures.count == 1)
    }

    @Test("A backslash on the last line of a tune still yields its music")
    func danglingBackslashAtEndOfInput() {
        let joined = staves("CDEF|\\")
        #expect(joined.count == 1)
        #expect(joined.first?.measures.count == 1)
    }
}
