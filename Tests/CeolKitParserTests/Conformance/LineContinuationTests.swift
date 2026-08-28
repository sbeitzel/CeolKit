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
