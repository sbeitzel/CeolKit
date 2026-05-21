// §14.2 Strspys.abc — two Scottish strathspeys demonstrating broken rhythm,
// tuplets, grace notes, and I:linebreak $.
import Testing
import CeolKitModel
import CeolKitParser

private let strspysABC = """
%abc-2.1
M:4/4
O:Scottish
R:Strathspey

X:1
T:A. A. Cameron's
K:D
e<A A2 B>G d>B|e<A A2 d>g (3fed|e<A A2 B>G d>B|B<G G>B d>g (3fed:|
B<e e>f g>e a>f|B<e e>f g>e (3fed|B<e e>f g>e a>f|d<B G>B d>g (3fed:|

X:2
T:Atholl Brose
I:linebreak $
K:D
{gcd}c<{e}A {gAGAG}A2 {gef}e>A {gAGAG}Ad|
{gcd}c<{e}A {gAGAG}A>e {ag}a>f {gef}e>d|
{gcd}c<{e}A {gAGAG}A2 {gef}e>A {gAGAG}Ad|
{g}c/d/e {g}G>{d}B {gf}gG {dc}d>B:|$
{g}c<e {gf}g>e {ag}a>e {gf}g>e|
{g}c<e {gf}g>e {ag}a2 {GdG}a>d|
{g}c<e {gf}g>e {ag}a>e {gf}g>f|
{gef}e>d {gf}g>d {gBd}B<{e}G {dc}d>B|
{g}c<e {gf}g>e {ag}a>e {gf}g>e|
{g}c<e {gf}g>e {ag}a2 {GdG}ad|
{g}c<{GdG}e {gf}ga {f}g>e {g}f>d|
{g}e/f/g {Gdc}d>c {gBd}B<{e}G {dc}d2|]
"""

@Suite("§14.2 Strspys.abc")
struct StrspysTests {

    let result = parse(strspysABC)
    var score: Score { result.score }

    // MARK: File-level

    @Test("File parses to strict dialect 2.1")
    func dialectIsStrict() {
        if case .strict(let version) = score.dialect {
            #expect(version == "2.1")
        } else {
            Issue.record("Expected strict dialect, got \(score.dialect)")
        }
    }

    @Test("File contains two tunes")
    func tuneCount() {
        #expect(score.tunes.count == 2)
    }

    @Test("Parse produces no error diagnostics")
    func noErrors() {
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    // MARK: File header fields apply to all tunes

    @Test("Tune 1 inherits file-header meter 4/4")
    func tune1Meter() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        if case .fraction(let num, let den) = tune.meter {
            #expect(num == 4)
            #expect(den == 4)
        } else {
            Issue.record("Expected .fraction(4, 4), got \(tune.meter)")
        }
    }

    // MARK: Tune 1 — A. A. Cameron's (broken rhythm, tuplets)

    @Test("Tune 1 key is D major")
    func tune1Key() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.key.tonic?.step == .d)
        #expect(tune.key.mode == .major)
    }

    @Test("Tune 1 title is 'A. A. Cameron's'")
    func tune1Title() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.titles.first?.value == "A. A. Cameron's")
    }

    @Test("Tune 1 first note is e (octave 4)")
    func tune1FirstNote() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first,
              let note = measure.noteEvents.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(note.pitch.step == .e)
        #expect(note.pitch.octave == 4)
    }

    @Test("Tune 1 first note has broken-left duration 1/2 (e<A)")
    func tune1FirstNoteBrokenLeft() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first,
              let note = measure.noteEvents.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(note.duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("Tune 1 second note A has broken-right duration 3/2 (e<A)")
    func tune1SecondNote() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        let notes = measure.noteEvents
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[1].pitch.step == .a)
        #expect(notes[1].pitch.octave == 3)
        #expect(notes[1].duration == Fraction(numerator: 3, denominator: 2))
    }

    @Test("Tune 1 contains at least one tuplet (3fed")
    func tune1HasTuplet() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        let tuplets = tune.singleVoiceMeasures.flatMap(\.tupletEvents)
        #expect(!tuplets.isEmpty)
    }

    @Test("Tune 1 tuplet has p=3 (three notes in time of two)")
    func tune1TupletP() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        let tuplets = tune.singleVoiceMeasures.flatMap(\.tupletEvents)
        guard let first = tuplets.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(first.p == 3)
        #expect(first.q == 2)
    }

    @Test("Tune 1 has repeat-end closing bar")
    func tune1HasRepeat() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        let hasRepeat = tune.singleVoiceMeasures.contains { $0.closingBar.kind == .repeatEnd }
        #expect(hasRepeat)
    }

    // MARK: Tune 2 — Atholl Brose (grace notes, I:linebreak $)

    @Test("Tune 2 title is 'Atholl Brose'")
    func tune2Title() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[1].titles.first?.value == "Atholl Brose")
    }

    @Test("Tune 2 key is D major")
    func tune2Key() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        #expect(tune.key.tonic?.step == .d)
        #expect(tune.key.mode == .major)
    }

    @Test("Tune 2 first measure contains grace groups")
    func tune2HasGraceNotes() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        let graces = tune.singleVoiceMeasures.flatMap(\.graceEvents)
        #expect(!graces.isEmpty)
    }

    @Test("Tune 2 grace groups are appoggiatura kind (open brace)")
    func tune2GraceKind() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        let graces = tune.singleVoiceMeasures.flatMap(\.graceEvents)
        guard let first = graces.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(first.kind == .appoggiatura)
    }

    @Test("Tune 2 $ produces a hard score line break")
    func tune2ScoreLineBreak() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        // After the $ sign, a new system begins — the measure before $ has a hard break
        let staves = tune.voices.first?.staves ?? []
        // With I:linebreak $, each $ in the source ends a system
        // We expect at least 2 staves (one system per $ separator)
        #expect(staves.count >= 2)
    }

    @Test("Tune 2 closes with final bar |]")
    func tune2FinalBar() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        let lastMeasure = tune.singleVoiceMeasures.last
        #expect(lastMeasure?.closingBar.kind == .final)
    }
}
