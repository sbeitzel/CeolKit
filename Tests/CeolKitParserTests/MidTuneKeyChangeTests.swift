import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #129: a `K:` written in the tune body changes the key from that point on
/// (§3.1.14, §7.3), and the measure where it happens has to say so — the renderer draws
/// the new signature there, and before this the change left no mark in the model at all.
///
/// `Measure.key` follows the convention `Measure.meter` already uses: non-nil only where
/// the key moved.
@Suite("A mid-tune K: lands on the measure it changes")
struct MidTuneKeyChangeTests {

    private func measures(_ abc: String, voice: Int = 0) -> [Measure] {
        let score = CeolKitParser().parse(abc, options: .default).score
        return score.tunes[0].voices[voice].staves.flatMap(\.measures)
    }

    /// The tonic letter and mode of a measure's key change, or `nil` where it carries none.
    private func key(_ measure: Measure) -> (DiatonicStep, Mode)? {
        guard let key = measure.key, let tonic = key.tonic else { return nil }
        return (tonic.step, key.mode)
    }

    // MARK: The two forms of the field

    @Test("A K: on its own line changes the key of the measure that follows it")
    func keyFieldOnItsOwnLine() throws {
        let bars = measures("""
        X:1
        T:Key change on its own line
        M:4/4
        L:1/4
        K:C
        CDEF|
        K:G
        GABC|
        """)
        try #require(bars.count == 2)

        #expect(bars[0].key == nil)
        #expect(key(bars[1])?.0 == .g)
        #expect(key(bars[1])?.1 == .major)
    }

    @Test("An inline [K:] against a bar line changes the key of the measure after it")
    func inlineKeyFieldAtABarLine() throws {
        let bars = measures("""
        X:1
        T:Key change inline
        M:4/4
        L:1/4
        K:C
        CDEF|[K:G]GABC|
        """)
        try #require(bars.count == 2)

        #expect(bars[0].key == nil)
        #expect(key(bars[1])?.0 == .g)
    }

    @Test("An inline [K:] part way through a bar lands on the bar it falls in")
    func inlineKeyFieldMidBar() throws {
        // A measure carries one signature, so there is nowhere finer for the change to go —
        // the same compromise a mid-bar `[L:]` makes (#122).
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        CD[K:G]EF|GABC|
        """)
        try #require(bars.count == 2)

        #expect(key(bars[0])?.0 == .g)
        #expect(bars[1].key == nil, "the key moved once; the next bar simply stays in it")
    }

    @Test("A K: in the last bar of a voice is still recorded")
    func keyChangeInTheFinalBar() throws {
        // The final measure is closed by `finaliseAccumulator`, not by a bar line, so it
        // takes its own copy of the pending change.
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        CDEF|[K:F]FGAB
        """)
        try #require(bars.count == 2)

        #expect(key(bars[1])?.0 == .f)
    }

    // MARK: What it does not do

    @Test("A K: before any music is the voice's opening key, not a change")
    func headerKeyIsNotAChange() throws {
        let abc = """
        X:1
        M:4/4
        L:1/4
        K:C
        V:1
        K:G
        GABc|defg|
        """
        let score = CeolKitParser().parse(abc, options: .default).score
        let voice = score.tunes[0].voices[0]

        #expect(voice.key?.tonic?.step == .g, "stated before any music, so it opens the voice")
        #expect(voice.staves.flatMap(\.measures).allSatisfy { $0.key == nil },
                "nothing changed part way through, so no measure carries a change")
    }

    @Test("A K: in one voice does not change another voice's measures")
    func keyChangeIsPerVoice() throws {
        // §7.3 asks for a field that sets a music property to be repeated in every voice it
        // should affect, so one voice's `K:` must not reach the rest.
        let abc = """
        X:1
        M:4/4
        L:1/4
        K:C
        V:1
        CDEF|[K:G]GABC|
        V:2
        CDEF|GABC|
        """
        let score = CeolKitParser().parse(abc, options: .default).score
        let first  = score.tunes[0].voices[0].staves.flatMap(\.measures)
        let second = score.tunes[0].voices[1].staves.flatMap(\.measures)
        try #require(first.count == 2 && second.count == 2)

        #expect(first[1].key?.tonic?.step == .g)
        #expect(second.allSatisfy { $0.key == nil })
    }

    // MARK: The change the model already showed

    @Test("The pitches after the change still resolve against the new key")
    func resolvedPitchesFollowTheChange() throws {
        // This part always worked — the accidental scope is re-seeded where the field is
        // met — and it has to keep working now that the change is also recorded.
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        FFFF|[K:G]FFFF|
        """)
        try #require(bars.count == 2)

        func alterations(_ measure: Measure) -> [Alteration] {
            measure.events.compactMap {
                if case .note(let n) = $0 { return n.pitch.alteration }
                return nil
            }
        }
        #expect(alterations(bars[0]).allSatisfy { $0 == .natural })
        #expect(alterations(bars[1]).allSatisfy { $0 == .sharp })
    }
}
