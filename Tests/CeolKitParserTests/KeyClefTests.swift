import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #126: `clef=` is legal on `K:` as well as on `V:` (ABC v2.2 §4.6), and only the
/// `V:` one used to reach anything — a tune whose clef was stated on its `K:` line was
/// drawn on a treble staff.
///
/// The clef is resolved once, in the semantic pass, into `VoiceProperties.clef`, so the
/// renderer keeps reading one place.  These assert what it resolves to.
@Suite("K: clef=")
struct KeyClefTests {

    private func clefs(_ body: String) -> [ClefSpec] {
        CeolKitParser().parse("""
        X:1
        T:Test
        M:4/4
        L:1/4
        \(body)
        """, options: .default).score.tunes[0].voices.map(\.properties.clef)
    }

    private func spec(_ clef: Clef, _ shift: Int = 0) -> ClefSpec {
        ClefSpec(clef: clef, octaveShift: shift)
    }

    @Test("A clef on the tune's own K: reaches the voice")
    func headerKeyClef() {
        #expect(clefs("K:E clef=bass\nCDEC|") == [spec(.bass)])
    }

    @Test("A tune that states no clef anywhere is still treble")
    func noClef() {
        #expect(clefs("K:E\nCDEC|") == [spec(.treble)])
    }

    @Test("The tune's K: clef reaches every voice that names none of its own")
    func headerKeyClefReachesAllVoices() {
        #expect(clefs("""
        K:E clef=bass
        V:1
        CDEC|
        V:2
        CDEC|
        """) == [spec(.bass), spec(.bass)])
    }

    @Test("A voice's own K: clef beats the tune's")
    func voiceKeyClef() {
        #expect(clefs("""
        K:E clef=bass
        V:1
        K:E clef=alto
        CDEC|
        V:2
        CDEC|
        """) == [spec(.alto), spec(.bass)])
    }

    @Test("A voice's own K: with no clef leaves the tune's standing")
    func voiceKeyWithoutClef() {
        #expect(clefs("""
        K:E clef=bass
        V:1
        K:A
        CDEC|
        """) == [spec(.bass)])
    }

    @Test("V: names the staff, so it wins over either K:")
    func voiceFieldBeatsKey() {
        #expect(clefs("K:E clef=bass\nV:1 clef=alto\nCDEC|") == [spec(.alto)])
        #expect(clefs("""
        K:E
        V:1 clef=alto
        K:E clef=bass
        CDEC|
        """) == [spec(.alto)])
    }

    @Test("The octave a K: clef is shifted by travels with it")
    func octaveShiftSurvives() {
        #expect(clefs("K:C clef=treble-8\nCDEC|") == [spec(.treble, -8)])
    }

    @Test("A K: clef part way through a voice does not reach back over its opening")
    func midTuneKeyClefIgnored() {
        // The renderer has one clef per voice for the whole tune, so a mid-tune change has
        // nowhere to live yet.  Leaving the voice on the clef it opened in is the honest
        // reading; applying the later one retroactively would be wrong for every bar
        // before it.
        #expect(clefs("K:C\nCDEC|\nK:C clef=bass\nCDEC|") == [spec(.treble)])
    }

    // A key named by a word used to be matched against the whole `K:` payload, so anything
    // written after the word made the field unparseable.  The word is one token like any
    // other now, and what follows it is read the same way it is after a tonic.

    @Test("K:none carries a clef like any other key, and is still K:none")
    func clefOnKeyNone() {
        let result = CeolKitParser().parse("""
        X:1
        T:Test
        L:1/4
        K:none clef=bass
        CDEC|
        """, options: .default)
        let tune = result.score.tunes[0]
        #expect(tune.key.tonic == nil)
        #expect(tune.key.mode == Mode.none)
        #expect(tune.voices[0].properties.clef == spec(.bass))
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("So do the two Highland pipe keys, which keep their case apart")
    func clefOnHighlandPipeKeys() {
        for (field, mode) in [("HP", Mode.highlandPipes), ("Hp", .highlandPipesNoSignature)] {
            let tune = CeolKitParser().parse("""
            X:1
            T:Test
            L:1/4
            K:\(field) clef=alto
            CDEC|
            """, options: .default).score.tunes[0]
            #expect(tune.key.mode == mode)
            #expect(tune.voices[0].properties.clef == spec(.alto))
        }
    }
}
