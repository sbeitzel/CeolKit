// Voice collection — issue #61.
//
// Two questions this file pins down: in what order do a tune's voices come out, and which
// voices come out at all.  Both used to be answered by the music body alone, which meant a
// header that declared V:1/V:2/V:3 could yield them in any other order, and a voice the body
// never switched into vanished with no diagnostic.
//
// Declaration order is what `%%score` (issue #62) places voices by, and a plan may name a
// voice the body never writes to — so both have to survive the semantic pass.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Voice order and declaration")
struct VoiceOrderTests {

    /// The voice ids of the first tune, in the order the model presents them.
    private func voiceIds(_ result: ParseResult) -> [String] {
        (result.score.firstTune?.voices ?? []).map { voice in
            switch voice.id {
            case .named(let name): name
            case .all:             "*"
            }
        }
    }

    private func voice(_ result: ParseResult, _ id: String) -> Voice? {
        result.score.firstTune?.voices.first { $0.id == .named(id) }
    }

    // MARK: Declaration order

    @Test("Voices come out in V: declaration order, not body order")
    func declarationOrderWinsOverBodyOrder() {
        // The body writes A before S; the header declared S first.  The header wins — the
        // order voices print in is the order the author declared them.
        let result = parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            V:S name="Soprano"
            V:A name="Alto"
            V:B name="Bass"
            K:C
            [V:A] CDEF|
            [V:S] GABc|
            [V:B] C,D,E,F,|
            """)
        #expect(voiceIds(result) == ["S", "A", "B"])
    }

    @Test("A body-only voice appends after every declared one")
    func bodyOnlyVoiceAppendsLast() {
        // X is never declared in the header, so it takes its place at the end — after the
        // voices the author did declare, in the order the body introduced it.
        let result = parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            V:S
            V:A
            K:C
            [V:X] CDEF|
            [V:A] GABc|
            [V:S] cdef|
            """)
        #expect(voiceIds(result) == ["S", "A", "X"])
    }

    @Test("A tune with no V: at all still has exactly one voice, \"1\"")
    func implicitSingleVoiceUnchanged() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF|GABc|\n")
        #expect(voiceIds(result) == ["1"])
        let measures = voice(result, "1")?.allMeasures ?? []
        #expect(measures.count == 2)
    }

    // MARK: Declared but never written to

    @Test("A header-declared voice the body never uses is still a voice, with empty staves")
    func unusedDeclaredVoiceSurvives() {
        let result = parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            V:S
            V:A
            V:B name="Bass"
            K:C
            [V:S] CDEF|
            [V:A] GABc|
            """)
        #expect(voiceIds(result) == ["S", "A", "B"])
        guard let bass = voice(result, "B") else {
            Issue.record("V:B was dropped")
            return
        }
        // It exists, it kept the properties it was declared with, and it holds no music.
        #expect(bass.properties.name == "Bass")
        #expect(bass.allMeasures.isEmpty)
        #expect(bass.isEmpty)
        // The voices that do have music are not marked empty.
        let soprano = voice(result, "S")
        #expect(soprano?.isEmpty == false)
    }

    @Test("A voice declared inline and never written to is a voice too")
    func unusedInlineVoiceSurvives() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:C\n[V:1] CDEF|\n[V:2]\n")
        #expect(voiceIds(result) == ["1", "2"])
        #expect(voice(result, "2")?.isEmpty == true)
    }

    @Test("Declaring voices does not conjure an empty implicit voice 1")
    func noPhantomDefaultVoice() {
        // "1" is the id the walker starts in when nothing else is declared.  A header that
        // names its own voices must not leave that placeholder behind as a silent staff.
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nV:S\nV:A\nK:C\n[V:S] CDEF|\n[V:A] GABc|\n")
        #expect(voiceIds(result) == ["S", "A"])
    }

    // MARK: Where unlabelled music goes

    @Test("Music before the first inline [V:] belongs to the first declared voice")
    func leadingMusicLandsInFirstDeclaredVoice() {
        // No [V:] has been seen when CDEF is walked.  It belongs to the voice at the top of
        // the score, not to a voice id the header never mentioned.
        let result = parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            V:S
            V:A
            K:C
            CDEF|
            [V:A] GABc|
            """)
        #expect(voiceIds(result) == ["S", "A"])
        let soprano = voice(result, "S")?.allMeasures ?? []
        #expect(soprano.count == 1)
        #expect(soprano.first?.noteEvents.count == 4)
    }
}
