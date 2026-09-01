import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #85: an inline `[L:]` or `[M:]` part way through a tune has to reach the beam
/// resolver, and reach it *where it was written*.
///
/// Both used to be voice-lifetime constants at beam time — the unit note length captured
/// when the voice's accumulator was first created, the meter read off the body context
/// after the whole body had been walked — so a tune that changed either had every one of
/// its measures beamed against the wrong one.
@Suite("Inline [L:] and [M:] reach the beam resolver")
struct InlineLengthAndMeterBeamingTests {

    private let quarter = Fraction(numerator: 1, denominator: 4)
    private let eighth  = Fraction(numerator: 1, denominator: 8)

    private func measures(_ abc: String, voice: Int = 0) -> [Measure] {
        let score = CeolKitParser().parse(abc, options: .default).score
        return score.tunes[0].voices[voice].staves.flatMap(\.measures)
    }

    /// The beam state of every note in a measure, in order.  Anything that is not a note is
    /// skipped: what a rest or a spacer does to beaming shows up in its neighbours.
    private func beams(_ measure: Measure) -> [BeamState] {
        measure.events.compactMap {
            if case .note(let n) = $0 { return n.beam }
            return nil
        }
    }

    // MARK: [L:]

    @Test("Notes after an inline [L:] are beamed against the new unit length")
    func inlineLengthReachesTheResolver() throws {
        let bars = measures("""
        X:1
        T:Unit length change
        M:4/4
        L:1/4
        K:C
        C D E F | [L:1/8] cdef gabc' |
        """)
        try #require(bars.count == 2)

        // L:1/4 in 4/4: a note is a whole beat, so nothing beams.
        #expect(beams(bars[0]) == [.single, .single, .single, .single])
        // L:1/8: half a beat, so each unspaced run of four beams together.
        #expect(beams(bars[1]) == [.start, .middle, .middle, .end,
                                   .start, .middle, .middle, .end])
    }

    @Test("The measure an inline [L:] falls in records the new unit length")
    func inlineLengthIsRecordedOnItsMeasure() throws {
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        C D E F | [L:1/8] cdef gabc' | cdef gabc' |
        """)
        try #require(bars.count == 3)

        #expect(bars[0].unitNoteLength == quarter)
        #expect(bars[1].unitNoteLength == eighth)
        // Not restated: every measure carries the effective value, so the change is simply
        // still there in the next bar (#122).
        #expect(bars[2].unitNoteLength == eighth)
        #expect(beams(bars[2]) == [.start, .middle, .middle, .end,
                                   .start, .middle, .middle, .end])
    }

    @Test("An [L:] at the head of a voice opens it rather than changing it")
    func headOfVoiceIsAnOpeningNotAChange() throws {
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        [L:1/8] cdef gabc' |
        """)
        try #require(bars.count == 1)
        // Recorded as the measure's own unit either way; what makes it an opening rather
        // than a change is that `Voice.unitNoteLength` moved with it.
        #expect(bars[0].unitNoteLength == eighth)
        #expect(beams(bars[0]) == [.start, .middle, .middle, .end,
                                   .start, .middle, .middle, .end])

        let voice = try #require(CeolKitParser().parse("""
        X:1
        M:4/4
        L:1/4
        K:C
        [L:1/8] cdef gabc' |
        """, options: .default).score.tunes[0].voices.first)
        #expect(voice.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("A [L:] met part way through a bar governs the bar it was written in")
    func midBarChangeLandsOnThatBar() throws {
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        C D | E [L:1/8] cdef |
        """)
        try #require(bars.count == 2)
        #expect(bars[0].unitNoteLength == quarter)
        #expect(bars[1].unitNoteLength == eighth)
    }

    @Test("An [L:] written against the bar line governs the bar after it")
    func changeAtTheBarLineLandsOnTheNextBar() throws {
        let bars = measures("""
        X:1
        M:4/4
        L:1/4
        K:C
        C D E F [L:1/8] | cdef gabc' |
        """)
        try #require(bars.count == 2)
        #expect(bars[0].unitNoteLength == quarter)
        #expect(bars[1].unitNoteLength == eighth)

        #expect(beams(bars[0]) == [.single, .single, .single, .single])
        #expect(beams(bars[1]) == [.start, .middle, .middle, .end,
                                   .start, .middle, .middle, .end])
    }

    // MARK: [M:]

    @Test("Measures either side of an inline [M:] are beamed against their own meter")
    func inlineMeterDoesNotReachBackwards() throws {
        // A quarter note is the whole beat in 4/4 and two thirds of it in 6/8, so the same
        // written run beams on one side of the change and not on the other.
        let bars = measures("""
        X:1
        M:4/4
        L:1/8
        K:C
        C2D2E2F2 | [M:6/8] C2D2E2 | C2D2E2 |
        """)
        try #require(bars.count == 3)

        #expect(beams(bars[0]) == [.single, .single, .single, .single])
        #expect(beams(bars[1]) == [.start, .middle, .end])
        #expect(beams(bars[2]) == [.start, .middle, .end])
    }

    @Test("An [M:] written against the bar line governs the bar after it")
    func meterAtTheBarLineLandsOnTheNextBar() throws {
        let bars = measures("""
        X:1
        M:4/4
        L:1/8
        K:C
        C2D2E2F2 [M:6/8] | C2D2E2 |
        """)
        try #require(bars.count == 2)
        #expect(bars[0].meter == nil)
        #expect(bars[1].meter != nil)

        #expect(beams(bars[0]) == [.single, .single, .single, .single])
        #expect(beams(bars[1]) == [.start, .middle, .end])
    }

    @Test("A mid-voice [L:] belongs to the voice that carries it")
    func changeDoesNotLeakToAnotherVoice() throws {
        let abc = """
        X:1
        M:4/4
        L:1/4
        K:C
        V:1
        V:2
        [V:1] C D | [L:1/8] cdef gabc' |
        [V:2] C D | cdef gabc' |
        """
        let one = measures(abc, voice: 0)
        let two = measures(abc, voice: 1)
        try #require(one.count == 2)
        try #require(two.count == 2)

        #expect(one[1].unitNoteLength == eighth)
        #expect(two[1].unitNoteLength == quarter)
        #expect(beams(one[1]) == [.start, .middle, .middle, .end,
                                  .start, .middle, .middle, .end])
        #expect(beams(two[1]) == Array(repeating: .single, count: 8))
    }

    @Test("A tune that changes neither is beamed as it always was")
    func unchangedTuneIsUnchanged() throws {
        let bars = measures("""
        X:1
        M:6/8
        L:1/8
        K:G
        GAB cBA | GAB d3 |
        """)
        try #require(bars.count == 2)
        #expect(bars.allSatisfy { $0.unitNoteLength == eighth })
        #expect(beams(bars[0]) == [.start, .middle, .end, .start, .middle, .end])
        #expect(beams(bars[1]) == [.start, .middle, .end, .single])
    }
}
