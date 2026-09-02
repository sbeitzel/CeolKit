// §7 Zocharti Loch — the standard's own worked example of multi-voice abc: four voices,
// two to a staff (`%%score (T1 T2) (B1 B2)`), octave clefs, `octave=` transposition, and a
// part that waits out the opening with invisible rests.
//
// The engraved side of the same source is asserted in
// `CeolKitSVGRendererTests/ZochartiLochConformanceTests.swift`.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("§7 Zocharti Loch")
struct ZochartiLochTests {

    let result = parse(zochartiLochABC)
    var score: Score { result.score }

    /// The four voices in `V:` order, or `nil` if the tune did not parse at all.
    private var voices: [Voice]? {
        guard let voices = score.firstTune?.voices, voices.count == 4 else { return nil }
        return voices
    }

    // MARK: - File level

    @Test("The example parses to exactly one tune, without error")
    func parsesCleanly() {
        #expect(score.tunes.count == 1)
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    @Test("No version line, so the dialect is loose")
    func dialectIsLoose() {
        // §2.1: a file without `%abc-2.1` or higher is read loosely, whatever else it uses.
        if case .loose = score.dialect {
            // expected
        } else {
            Issue.record("Expected loose dialect, got \(score.dialect)")
        }
    }

    // MARK: - Header fields

    @Test("Title and composer")
    func titleAndComposer() {
        #expect(score.firstTune?.titles.first?.value == "Zocharti Loch")
        #expect(score.firstTune?.metadata.composer?.value == "Louis Lewandowski (1821-1894)")
    }

    @Test("Meter is common time")
    func meter() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        if case .commonTime = tune.meter {
            // expected
        } else {
            Issue.record("Expected .commonTime, got \(tune.meter)")
        }
    }

    @Test("No L: field, so the unit note length comes from the meter: 1/8")
    func unitNoteLength() {
        // §3.1.7: C is 4/4, which is ≥ 0.75, so the default unit length is an eighth — the
        // reason `x8` and `d6` in the body are a full bar and a dotted half.
        #expect(score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("Tempo is 76 to the quarter, with no prelude text")
    func tempo() {
        guard let tempo = score.firstTune?.tempo else { Issue.record("No tempo found"); return }
        #expect(tempo.bpm == 76.0)
        #expect(tempo.beats == [Fraction(numerator: 1, denominator: 4)])
        #expect(tempo.prelude == nil)
    }

    @Test("Key is G minor")
    func key() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.key.tonic?.step == .g)
        #expect(tune.key.tonic?.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(tune.key.mode == .minor)
    }

    // MARK: - Voices

    @Test("Four voices, in V: declaration order")
    func voiceOrder() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices.map(\.id) == [.named("T1"), .named("T2"), .named("B1"), .named("B2")])
    }

    @Test("The tenors are on an octave-down treble clef")
    func tenorClefs() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices.prefix(2) {
            #expect(voice.properties.clef.clef == .treble)
            #expect(voice.properties.clef.octaveShift == -8, "\(voice.id) lost its `-8`")
        }
    }

    @Test("The basses are on a plain bass clef and sound an octave down")
    func bassClefsAndTransposition() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices.suffix(2) {
            #expect(voice.properties.clef.clef == .bass)
            // `octave=-2` is a sounding transposition, not a clef: the notes are written
            // where the bass clef puts them and the shift is carried beside them.
            #expect(voice.properties.clef.octaveShift == 0)
            #expect(voice.properties.transposition.octave == -2, "\(voice.id) lost its `octave=`")
        }
    }

    @Test("Every voice carries the name and the abbreviated snm= it was given")
    func namesAndSubnames() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices.map(\.properties.name) == ["Tenore I", "Tenore II", "Basso I", "Basso II"])
        #expect(voices.map(\.properties.subname) == ["T.I", "T.II", "B.I", "B.II"])
    }

    // MARK: - Staff plan (§11.1)

    @Test("%%score (T1 T2) (B1 B2) puts two voices on each of two staves")
    func staffPlan() throws {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        let plan = tune.directives.compactMap { scoped -> StaffPlan? in
            if case .staffPlan(let plan) = scoped.directive { return plan }
            return nil
        }
        try #require(plan.count == 1)
        let layout = plan[0].layout
        #expect(layout.staves == [[.named("T1"), .named("T2")], [.named("B1"), .named("B2")]])
        // `( … )` and nothing else: no brace, no bracket, and no `|`, so the staves are
        // neither joined by furniture nor by their bar lines.
        #expect(layout.spans.isEmpty)
        #expect(layout.barlineJoins.isEmpty)
        #expect(layout.floating.isEmpty)
    }

    @Test("The plan is tune-global, and takes effect from the first stave")
    func staffPlanScope() throws {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        try #require(tune.staffPlans.count == 1)
        // Written in the tune header, so it governs from the body's first stave.
        #expect(tune.staffPlans[0].effectiveFromStave == 0)
        let scoped = tune.directives.filter {
            if case .staffPlan = $0.directive { return true }
            return false
        }
        try #require(scoped.count == 1)
        if case .tuneGlobal = scoped[0].scope {
            // expected
        } else {
            Issue.record("The plan is scoped \(scoped[0].scope), not tune-global")
        }
    }

    // MARK: - Body

    @Test("Every voice is written as two staves of four bars")
    func staveShape() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices {
            #expect(voice.staves.map(\.measures.count) == [4, 4], "\(voice.id) is shaped wrong")
        }
    }

    @Test("B2 waits out its first five bars on invisible rests")
    func invisibleRests() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        let b2 = voices[3]
        // `x8` fills the bar without drawing anything — the idiomatic way to keep a
        // shared-staff voice's bar count right before it enters.
        let openingBars = b2.allMeasures.prefix(5)
        for (index, measure) in openingBars.enumerated() {
            #expect(measure.noteEvents.isEmpty, "bar \(index + 1) of B2 has notes")
            #expect(measure.restEvents.map(\.kind) == [.invisible],
                    "bar \(index + 1) of B2 is not one invisible rest")
        }
        // And it does enter: bar 6 is `z2B2 c2d2`, so from there on B2 has notes.
        #expect(!b2.allMeasures[5].noteEvents.isEmpty)
    }

    @Test("B1's rests before it enters are visible ones")
    func visibleRests() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        // The distinction is the whole point of `x` against `z`: B1's `z8` is drawn as a
        // whole-bar rest, B2's `x8` is not drawn at all.
        #expect(voices[2].allMeasures[0].restEvents.map(\.kind) == [.normal])
    }

    @Test("The opening slur of each tenor spans its first four notes")
    func openingSlurs() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices.prefix(2) {
            guard let bar = voice.firstMeasure else { Issue.record("\(voice.id) has no bars"); return }
            let notes = bar.noteEvents
            #expect(notes.count == 4)
            #expect(notes.first?.slurs.opens == 1, "\(voice.id) opens no slur")
            #expect(notes.last?.slurs.closes == 1, "\(voice.id) closes no slur")
        }
    }

    @Test("H is read as a fermata, on the last note of every voice")
    func fermatas() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices {
            guard let last = voice.allMeasures.last?.noteEvents.last else {
                Issue.record("\(voice.id) ends on no note"); return
            }
            #expect(last.decorations.contains(.fermata), "\(voice.id) lost its H")
        }
    }

    @Test("B1's ^f is an explicit sharp in G minor")
    func explicitAccidental() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        guard let last = voices[2].allMeasures.last?.noteEvents.last else {
            Issue.record("B1 ends on no note"); return
        }
        // The leading tone: written `^f`, and G minor's key signature does not supply it.
        #expect(last.pitch.step == .f)
        #expect(last.writtenAccidental == Alteration(numerator: 1, denominator: 1))
        #expect(last.displayedAccidental == Alteration(numerator: 1, denominator: 1))
    }

    @Test("Each half closes on a double bar")
    func closingBars() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        for voice in voices {
            #expect(voice.allMeasures.last?.closingBar.kind == .double, "\(voice.id) ends wrong")
        }
    }

    @Test("The bar numbering the % remarks describe is what parsed")
    func barCount() {
        guard let voices else { Issue.record("Parser prerequisite not met"); return }
        // Eight bars per voice, thirty-two in all — the remark lines say 1 and 5, and the
        // comments themselves leave no trace in the model.
        #expect(voices.map(\.allMeasures.count) == [8, 8, 8, 8])
    }
}

/// §7 of the ABC v2.2 standard, verbatim.
let zochartiLochABC = """
X:1
T:Zocharti Loch
C:Louis Lewandowski (1821-1894)
M:C
Q:1/4=76
%%score (T1 T2) (B1 B2)
V:T1  clef=treble-8  name="Tenore I"   snm="T.I"
V:T2  clef=treble-8  name="Tenore II"  snm="T.II"
V:B1  clef=bass      name="Basso I"    snm="B.I"  octave=-2
V:B2  clef=bass      name="Basso II"   snm="B.II" octave=-2
K:Gm
%            End of header, start of tune body:
% 1
[V:T1]  (B2c2 d2g2)  | f6e2      | (d2c2 d2)e2 | d4 c2z2 |
[V:T2]  (G2A2 B2e2)  | d6c2      | (B2A2 B2)c2 | B4 A2z2 |
[V:B1]       z8      | z2f2 g2a2 | b2z2 z2 e2  | f4 f2z2 |
[V:B2]       x8      |     x8    |      x8     |    x8   |
% 5
[V:T1]  (B2c2 d2g2)  | f8        | d3c (d2fe)  | H d6    ||
[V:T2]       z8      |     z8    | B3A (B2c2)  | H A6    ||
[V:B1]  (d2f2 b2e'2) | d'8       | g3g  g4     | H^f6    ||
[V:B2]       x8      | z2B2 c2d2 | e3e (d2c2)  | H d6    ||
"""
