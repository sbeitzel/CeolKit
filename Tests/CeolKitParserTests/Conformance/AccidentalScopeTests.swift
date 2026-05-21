// Accidental scoping conformance tests. ABC §4.2.
// An accidental in a measure applies to all subsequent notes of the same
// pitch class and octave in that measure; it resets at each bar line.
import Testing
import CeolKitModel
import CeolKitParser

private func scopeTune(_ body: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(body)"
}

@Suite("Accidental Scoping")
struct AccidentalScopeTests {

    // MARK: Key-signature accidentals

    @Test("In K:G, plain F has pitch alteration +1/1 (F# from key)")
    func keySignatureSharp() {
        let result = parse("X:1\nT:Test\nM:4/4\nL:1/4\nK:G\nFGAB|")
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .f)
        #expect(note?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(note?.writtenAccidental == nil)
    }

    @Test("In K:C, plain F has natural pitch alteration 0/1")
    func noKeySignature() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:C\nF|")
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .f)
        #expect(note?.pitch.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(note?.writtenAccidental == nil)
        #expect(note?.displayedAccidental == nil)
    }

    // MARK: Written accidental carries through bar

    @Test("^c c in one measure: second c is also sharp (intra-bar memory)")
    func intraBarpSharpMemory() {
        let result = parse(scopeTune("^c c2|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // First c: written and displayed sharp
        #expect(notes[0].writtenAccidental == Alteration(numerator: 1, denominator: 1))
        // Second c: no written accidental, but pitch is still sharp
        #expect(notes[1].writtenAccidental == nil)
        #expect(notes[1].pitch.alteration == Alteration(numerator: 1, denominator: 1))
        // Renderer should NOT draw the sharp again (key sig handles nothing, bar scope does)
        // displayedAccidental is nil for the second c (accidental already established in bar)
        #expect(notes[1].displayedAccidental == nil)
    }

    @Test("^c | c across bar line: second c returns to key signature (C natural in K:C)")
    func barLineResetsAccidental() {
        let result = parse(scopeTune("^c |c|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        guard measures.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // First measure: c is sharp
        let firstC = measures[0].noteEvents.first
        #expect(firstC?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
        // Second measure: c is natural (K:C has no sharps)
        let secondC = measures[1].noteEvents.first
        #expect(secondC?.pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("=f in K:G: writtenAccidental is natural, displayedAccidental is natural")
    func naturalCancelsPrevious() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:G\n=f|")
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 0, denominator: 1))
        // Renderer must draw the natural sign because the key has F#
        #expect(note?.displayedAccidental == Alteration(numerator: 0, denominator: 1))
        #expect(note?.pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("=f f in K:G: second f is natural (natural carries through bar)")
    func naturalCarriesThrough() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:G\n=f f2|")
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // Second f still natural in bar
        #expect(notes[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
        // displayedAccidental: nil (natural already shown on first f)
        #expect(notes[1].displayedAccidental == nil)
    }

    @Test("Accidental only applies to same octave: ^c C in K:C — C (uppercase) stays natural")
    func accidentalOctaveScope() {
        let result = parse(scopeTune("^c C2|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // Second note is uppercase C (octave 3), different octave from the ^c (octave 4)
        #expect(notes[1].pitch.octave == 3)
        #expect(notes[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("_b in K:G doesn't affect B (uppercase, different octave)")
    func flatOnlyAffectsSameOctave() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:G\n_b B2|")
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // b (octave 4) is flat
        #expect(notes[0].pitch.octave == 4)
        #expect(notes[0].pitch.alteration == Alteration(numerator: -1, denominator: 1))
        // B (octave 3) is unaffected — stays natural in K:G
        #expect(notes[1].pitch.octave == 3)
        #expect(notes[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    // MARK: displayedAccidental vs writtenAccidental

    @Test("First note with accidental has same written and displayed accidental")
    func firstAccidentalBoth() {
        let result = parse(scopeTune("^c|"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 1, denominator: 1))
        #expect(note?.displayedAccidental == Alteration(numerator: 1, denominator: 1))
    }

    @Test("Redundant accidental in bar: written != nil, displayed == nil")
    func redundantAccidental() {
        // In K:G, F is already sharp. Writing ^f is redundant.
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:G\n^f|")
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        // Written accidental is ^ (sharp)
        #expect(note?.writtenAccidental == Alteration(numerator: 1, denominator: 1))
        // displayedAccidental: nil or sharp — depends on convention.
        // The spec says displayedAccidental is "what should be printed after key sig & bar scope".
        // A redundant sharp in K:G: whether to display it is renderer's choice, but the model
        // should record it. Per common practice, courtesy accidentals may still display.
        // The model stores what a renderer SHOULD draw — for a redundant sharp, this is nil
        // (the key signature already shows it).
        #expect(note?.displayedAccidental == nil)
    }
}
