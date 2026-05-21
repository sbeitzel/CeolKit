// Note duration and broken-rhythm conformance tests. ABC §4.3–4.5.
// All assertions use L:1/8 to make duration fractions concrete.
import Testing
import CeolKitModel
import CeolKitParser

private func rhythmTune(_ body: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/8\nK:C\n\(body)"
}

@Suite("Note Rhythm and Duration")
struct NoteRhythmTests {

    // MARK: Basic lengths (L:1/8)

    @Test("Plain note has duration 1 unit")
    func plainNoteDuration() {
        let result = parse(rhythmTune("C|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 1, denominator: 1))
    }

    @Test("C2 has duration 2 units")
    func doubledNote() {
        let result = parse(rhythmTune("C2|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 2, denominator: 1))
    }

    @Test("C4 has duration 4 units")
    func quadrupledNote() {
        let result = parse(rhythmTune("C4|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 4, denominator: 1))
    }

    @Test("C3/2 has duration 3/2 units (dotted)")
    func dottedNote() {
        let result = parse(rhythmTune("C3/2|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 3, denominator: 2))
    }

    @Test("C/ has duration 1/2 units")
    func halvedException() {
        let result = parse(rhythmTune("C/|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("C/2 has duration 1/2 units")
    func halfByExplicitDivisor() {
        let result = parse(rhythmTune("C/2|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("C// has duration 1/4 units (double-slash)")
    func doubleSlashNote() {
        let result = parse(rhythmTune("C//|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 1, denominator: 4))
    }

    @Test("C/4 has duration 1/4 units")
    func quarterNote() {
        let result = parse(rhythmTune("C/4|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.duration == Fraction(numerator: 1, denominator: 4))
    }

    // MARK: Broken rhythm

    @Test("C>D: C gets 3/2 (broken right, longer)")
    func brokenRightFirstNote() {
        let result = parse(rhythmTune("C>D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 1 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].duration == Fraction(numerator: 3, denominator: 2))
    }

    @Test("C>D: D gets 1/2 (broken right, shorter)")
    func brokenRightSecondNote() {
        let result = parse(rhythmTune("C>D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[1].duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("C<D: C gets 1/2 (broken left, shorter)")
    func brokenLeftFirstNote() {
        let result = parse(rhythmTune("C<D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 1 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("C<D: D gets 3/2 (broken left, longer)")
    func brokenLeftSecondNote() {
        let result = parse(rhythmTune("C<D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[1].duration == Fraction(numerator: 3, denominator: 2))
    }

    @Test("C>>D: C gets 7/4 (double broken right)")
    func doublebrokenRight() {
        let result = parse(rhythmTune("C>>D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 1 else { Issue.record("Parser prerequisite not met"); return }
        // >> means C gets 7/4 and D gets 1/4 of their unit-note-length duration
        #expect(notes[0].duration == Fraction(numerator: 7, denominator: 4))
    }

    @Test("C>>D: D gets 1/4 (double broken right)")
    func doublebrokenRightSecond() {
        let result = parse(rhythmTune("C>>D|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[1].duration == Fraction(numerator: 1, denominator: 4))
    }

    // MARK: Rests

    @Test("z rest has duration 1 unit")
    func normalRest() {
        let result = parse(rhythmTune("z|"))
        let rest = result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first
        #expect(rest?.kind == .normal)
        #expect(rest?.duration == Fraction(numerator: 1, denominator: 1))
    }

    @Test("z2 rest has duration 2 units")
    func doubledRest() {
        let result = parse(rhythmTune("z2|"))
        let rest = result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first
        #expect(rest?.duration == Fraction(numerator: 2, denominator: 1))
    }

    @Test("x rest is invisible and has duration 1")
    func invisibleRest() {
        let result = parse(rhythmTune("x|"))
        let rest = result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first
        #expect(rest?.kind == .invisible)
        #expect(rest?.duration == Fraction(numerator: 1, denominator: 1))
    }

    @Test("Z rest is a full-measure rest")
    func fullMeasureRest() {
        let result = parse(rhythmTune("Z|"))
        let rest = result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first
        #expect(rest?.kind == .fullMeasure)
    }

    @Test("X rest is an invisible full-measure rest")
    func invisibleFullMeasureRest() {
        let result = parse(rhythmTune("X|"))
        let rest = result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first
        #expect(rest?.kind == .fullMeasureInvisible)
    }

    // MARK: Tuplets

    @Test("(3abc creates a triplet with p=3 q=2")
    func triplet() {
        let result = parse(rhythmTune("(3abc|"))
        let tuplets = result.score.firstTune?.singleVoiceMeasures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tuplet.p == 3)
        #expect(tuplet.q == 2)
        #expect(tuplet.r == 3)
    }

    @Test("(3abc triplet contains 3 events")
    func tripletEventCount() {
        let result = parse(rhythmTune("(3abc|"))
        let tuplets = result.score.firstTune?.singleVoiceMeasures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tuplet.events.count == 3)
    }

    @Test("(3:2:3 explicit tuplet has p=3 q=2 r=3")
    func explicitTuplet() {
        let result = parse(rhythmTune("(3:2:3abc|"))
        let tuplets = result.score.firstTune?.singleVoiceMeasures.first?.tupletEvents ?? []
        guard let tuplet = tuplets.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tuplet.p == 3)
        #expect(tuplet.q == 2)
        #expect(tuplet.r == 3)
    }

    // MARK: Ties

    @Test("C-C creates a tied pair")
    func tiedNotes() {
        let result = parse(rhythmTune("C2-C2|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].ties == .startsTie)
        #expect(notes[1].ties == .endsTie)
    }

    @Test("Tie chain C-C-C uses continuesTie for middle note")
    func tieChain() {
        let result = parse(rhythmTune("C-C-C2|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].ties == .startsTie)
        #expect(notes[1].ties == .continuesTie)
        #expect(notes[2].ties == .endsTie)
    }

    // MARK: Beams

    @Test("cdeg (no whitespace) forms a beam group")
    func beamGroup() {
        // With L:1/8, notes shorter than L (L/2 = 1/16) can't be beamed...
        // Actually notes equal to L (=1/8) ARE shorter than the beat (1/4 in 4/4),
        // so they are beamable.
        let result = parse(rhythmTune("cdeg|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 4 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].beam == .start)
        #expect(notes[1].beam == .middle)
        #expect(notes[2].beam == .middle)
        #expect(notes[3].beam == .end)
    }

    @Test("c d (with space) breaks the beam")
    func beamBreak() {
        let result = parse(rhythmTune("c d|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].beam == .single)
        #expect(notes[1].beam == .single)
    }

    @Test("Quarter note C4 is not beamable (beam = .single)")
    func quarterNoteNotBeamed() {
        // L:1/8 so C4 = 4/8 = 1/2 note. Not shorter than L, so not beamable.
        let result = parse(rhythmTune("C4D4|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[0].beam == .single)
        #expect(notes[1].beam == .single)
    }
}
