import Testing
import CeolKitModel
import CeolKitParser

/// Issue #307: a broken rhythm (`<`, `>`) reaches the note on each side of it across anything
/// that is not a note, rest or chord — a slur, a grace group, a decoration, a chord symbol or an
/// annotation — as abcm2ps applies it.  `e2>(a2 a4)` used to leave the `a2` its written length,
/// because the multiplier went to the slur.
@Suite("Broken rhythm across slurs and other marks (#307)")
struct BrokenRhythmSlurTests {

    /// The duration of every note, chord and rest of the tune, in units of `L:`, in order.
    private func durations(_ body: String) -> [Fraction] {
        let abc = "X:1\nL:1/16\nK:D\n\(body)\n"
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        return tune.singleVoiceMeasures.flatMap(\.events).compactMap { event in
            switch event {
            case .note(let n):  return n.duration
            case .rest(let r):  return r.duration
            case .chord(let c): return c.duration
            default:            return nil
            }
        }
    }

    private func f(_ n: Int, _ d: Int = 1) -> Fraction { Fraction(numerator: n, denominator: d) }

    @Test("The issue's bars: a tie and a slur after the broken rhythm agree")
    func issueBars() {
        #expect(durations("[| e2>a2- a4 | e2>(a2 a4) |]") == [f(3), f(1), f(4), f(3), f(1), f(4)])
    }

    @Test("A slur opening on the left-hand note")
    func slurAroundPair() {
        #expect(durations("(e2>a2) a4 |") == [f(3), f(1), f(4)])
    }

    @Test("A slur closing on the left-hand note")
    func slurCloseBeforeSymbol() {
        #expect(durations("(c2 e2)>a2 a2 |") == [f(2), f(3), f(1), f(2)])
    }

    @Test("< before a slur")
    func leftBeforeSlur() {
        #expect(durations("e2<(a2 a4) |") == [f(1), f(3), f(4)])
    }

    @Test("A decoration on the right-hand note")
    func decoration() {
        #expect(durations("e2>!trill!a2 a4 |") == [f(3), f(1), f(4)])
        #expect(durations("e2>Ta2 a4 |") == [f(3), f(1), f(4)])
    }

    @Test("A chord symbol or annotation on the right-hand note")
    func chordSymbolAndAnnotation() {
        #expect(durations("e2>\"D\"a2 a4 |") == [f(3), f(1), f(4)])
        #expect(durations("e2>\"^hi\"a2 a4 |") == [f(3), f(1), f(4)])
    }

    @Test("A grace group and a slur together, and grace notes keep their length")
    func graceAndSlur() {
        let abc = "X:1\nL:1/16\nK:D\ne2>({g}a2 a4) |\n"
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        let notes = tune.singleVoiceMeasures.flatMap(\.events).compactMap { event -> Note? in
            if case .note(let n) = event { return n }
            return nil
        }
        #expect(notes.map(\.duration) == [f(3), f(1), f(4)])
    }

    @Test("A grace group before the broken rhythm leaves the left-hand note found")
    func graceBeforeSymbol() {
        #expect(durations("e2{g}>a2 a4 |") == [f(3), f(1), f(4)])
    }

    @Test("A bar line stops the search")
    func barLineStops() {
        #expect(durations("e2>| a2 a4 |") == [f(3), f(2), f(4)])
    }
}
