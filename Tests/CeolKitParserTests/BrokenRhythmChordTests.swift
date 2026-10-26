import Testing
import CeolKitModel
import CeolKitParser

/// Issue #238: a broken rhythm (`<`, `>`) next to a chord lengthens or shortens the chord the
/// same way it does a single note, as abcm2ps applies it.  Both chords used to keep the length
/// they were written with.
@Suite("Broken rhythm on chords (#238)")
struct BrokenRhythmChordTests {

    /// The duration of every note, chord and rest of the tune, in units of `L:`, in order —
    /// and, for a chord, that every one of its notes has the chord's duration.
    private func durations(_ body: String) -> [Fraction] {
        let abc = "X:1\nM:2/4\nL:1/8\nK:D\n\(body)\n"
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        return tune.singleVoiceMeasures.flatMap(\.events).compactMap { event in
            switch event {
            case .note(let n): return n.duration
            case .rest(let r): return r.duration
            case .chord(let c):
                #expect(c.notes.allSatisfy { $0.duration == c.duration })
                return c.duration
            default:           return nil
            }
        }
    }

    private func f(_ n: Int, _ d: Int = 1) -> Fraction { Fraction(numerator: n, denominator: d) }

    @Test("The issue's bars: < and << between chords with note lengths")
    func betweenChords() {
        #expect(durations("[B2d2]<[A2c2] | [B2d2]<<[A2c2] z |")
                == [f(1), f(3), f(1, 2), f(7, 2), f(1)])
    }

    @Test("A chord's own length takes the multiplier too")
    func chordLength() {
        #expect(durations("[Bd]2>[Ac]2 |") == [f(3), f(1)])
    }

    @Test("A broken rhythm between a chord and a note")
    func chordAndNote() {
        #expect(durations("[Bd]>A A<[Bd] |") == [f(3, 2), f(1, 2), f(1, 2), f(3, 2)])
    }
}
