import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #224: `octave=` "raises (positive number) or lowers (negative number) the music code
/// in the current voice by one or more octaves" (ABC v2.2 §4.6).  `V:` read it into
/// `VoiceProperties.transposition` and nothing consulted it; `K:` did not read it at all.
///
/// It moves the music, so it is applied to `Note.pitch` — what abcm2ps's `get_note` does to
/// a note's pitch as it is read.  Scoped as abcm2ps scopes it: a header `K:` covers every
/// voice, a body `K:` or a `V:` its own voice, and each lasts until another `octave=`
/// replaces it.
@Suite("octave= on K: and V:")
struct OctaveModifierTests {

    /// The pitch of every note in voice `index`, in order — grace notes, chord notes and
    /// tuplet notes included, since `octave=` moves all of them.
    private func pitches(_ abc: String, voice index: Int = 0) -> [String] {
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        func walk(_ event: Event) -> [Note] {
            switch event {
            case .note(let n):   return [n]
            case .chord(let c):  return c.notes
            case .grace(let g):  return g.notes
            case .tuplet(let t): return t.events.flatMap(walk)
            default:             return []
            }
        }
        return tune.voices[index].staves.flatMap(\.measures).flatMap(\.events).flatMap(walk)
            .map { "\($0.pitch.step)\($0.pitch.octave)" }
    }

    // MARK: - The bug as filed

    /// §4.6's own pair, which it gives as two ways of writing the same thing.
    @Test("K: clef=bass octave=-1 CDEF is C,D,E,F,")
    func standardExample() {
        let shifted = pitches("""
            X:1
            L:1/4
            K:C clef=bass octave=-1
            CDEF|GABc|
            """)
        let written = pitches("""
            X:1
            L:1/4
            K:C clef=bass
            C,D,E,F,|G,A,B,C|
            """)
        #expect(shifted == ["c3", "d3", "e3", "f3", "g3", "a3", "b3", "c4"])
        #expect(shifted == written)
    }

    @Test("V: octave= moves that voice and no other")
    func voiceOctave() {
        let abc = """
            X:1
            L:1/4
            V:1
            V:2 octave=-2
            K:C
            [V:1] c d e f|
            [V:2] c d e f|
            """
        #expect(pitches(abc, voice: 0) == ["c5", "d5", "e5", "f5"])
        #expect(pitches(abc, voice: 1) == ["c3", "d3", "e3", "f3"])
    }

    @Test("octave= moves chord notes, grace notes and tuplet notes too")
    func everyNote() {
        #expect(pitches("""
            X:1
            L:1/8
            K:C octave=1
            [CE] {G}A (3Bcd|
            """) == ["c5", "e5", "g5", "a5", "b5", "c6", "d6"])
    }

    // MARK: - Scope

    @Test("A header K: octave= covers every voice")
    func headerKeyCoversEveryVoice() {
        let abc = """
            X:1
            L:1/4
            V:1
            V:2
            K:C octave=1
            [V:1] C|
            [V:2] C|
            """
        #expect(pitches(abc, voice: 0) == ["c5"])
        #expect(pitches(abc, voice: 1) == ["c5"])
    }

    /// The `K:` names its key as well: one that states only options, `[K:octave=-1]`, is
    /// not yet read as a key at all (#223).
    @Test("A body K: octave= belongs to the voice it is written in")
    func bodyKeyIsPerVoice() {
        let abc = """
            X:1
            L:1/4
            V:1
            V:2
            K:C
            [V:1] C [K:C octave=-1] C|
            [V:2] C C|
            """
        #expect(pitches(abc, voice: 0) == ["c4", "c3"])
        #expect(pitches(abc, voice: 1) == ["c4", "c4"])
    }

    @Test("A K: or V: that states no octave leaves the voice's alone")
    func unstatedLeavesItAlone() {
        #expect(pitches("""
            X:1
            L:1/4
            V:1 octave=-1
            K:C
            [V:1] C [K:clef=bass] C [V:1 clef=bass] C|
            """) == ["c3", "c3", "c3"])
    }

    @Test("octave=0 puts it back")
    func zeroResets() {
        #expect(pitches("""
            X:1
            L:1/4
            K:C octave=-1
            C [K:C octave=0] C|
            """) == ["c3", "c4"])
        #expect(pitches("""
            X:1
            L:1/4
            V:1 octave=2
            K:C
            [V:1] C [V:1 octave=0] C|
            """) == ["c6", "c4"])
    }

    // MARK: - Accidentals

    /// Bar memory is kept by the pitch a note sounds at, which is the moved one; moving every
    /// note of the voice by the same amount keeps `^C … C` reading as it did.
    @Test("An accidental carries through the bar under octave=")
    func accidentalMemory() throws {
        let tune = CeolKitParser().parse("""
            X:1
            L:1/4
            K:C octave=-1
            ^C C c C|
            """, options: .default).score.tunes[0]
        let notes = tune.voices[0].staves[0].measures[0].events.compactMap { event -> Note? in
            if case .note(let n) = event { return n } else { return nil }
        }
        let sharp = Alteration(numerator: 1, denominator: 1)
        #expect(notes.map(\.pitch.alteration) == [sharp, sharp, .natural, sharp])
        #expect(notes.map(\.pitch.octave) == [3, 3, 4, 3])
    }

    // MARK: - The field

    @Test("K: reads octave= and records that it was stated")
    func keyField() {
        let tune = CeolKitParser().parse("""
            X:1
            K:C clef=bass octave=-2
            C|
            """, options: .default).score.tunes[0]
        let key = tune.key
        #expect(key.transposition.octave == -2)
        #expect(key.transposition.statesOctave)
    }

    @Test("octave=0 is stated; silence is not")
    func statedZero() {
        #expect(Transposition(semitones: 0, octave: 0, statesOctave: true) != .none)
        #expect(!Transposition.none.statesOctave)
        #expect(Transposition(semitones: 0, octave: -1).statesOctave)
    }
}
