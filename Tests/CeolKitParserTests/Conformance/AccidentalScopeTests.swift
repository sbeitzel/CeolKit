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
        // Second note is uppercase C (octave 4), different octave from the ^c (octave 5)
        #expect(notes[1].pitch.octave == 4)
        #expect(notes[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("_b in K:G doesn't affect B (uppercase, different octave)")
    func flatOnlyAffectsSameOctave() {
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:G\n_b B2|")
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // b (octave 5) is flat
        #expect(notes[0].pitch.octave == 5)
        #expect(notes[0].pitch.alteration == Alteration(numerator: -1, denominator: 1))
        // B (octave 4) is unaffected — stays natural in K:G
        #expect(notes[1].pitch.octave == 4)
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

    // MARK: Per-voice scope — issue #60

    /// §4.2 scopes a written accidental to the rest of the bar *in the voice that wrote it*.
    ///
    /// Every tune below switches voice **mid-bar**, which is the shape that exposes a shared
    /// scope. A voice line that ends on a bar line hides the bug: the bar reset fires before
    /// the next voice is walked, so the leaked memory is cleared on the way past.
    private func voiceMeasures(_ result: ParseResult, _ id: String) -> [Measure] {
        result.score.firstTune?.voices.first { $0.id == .named(id) }?.allMeasures ?? []
    }

    private static let twoVoiceHeader = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nV:1\nV:2\n"

    @Test("^F in voice 1 does not sharpen voice 2's F in the same bar")
    func accidentalDoesNotLeakForward() {
        let result = parse(Self.twoVoiceHeader + "[V:1] ^F F [V:2] F F|\n")
        let one = voiceMeasures(result, "1").first?.noteEvents ?? []
        let two = voiceMeasures(result, "2").first?.noteEvents ?? []
        guard one.count >= 2, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // Voice 1 keeps its own bar memory: the second F is still sharp, and undrawn.
        #expect(one[0].pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(one[1].pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(one[1].displayedAccidental == nil)
        // Voice 2 wrote no accidental, so both its Fs are natural and neither draws one.
        #expect(two[0].pitch.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(two[0].displayedAccidental == nil)
        #expect(two[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(two[1].displayedAccidental == nil)
    }

    @Test("The reverse ordering behaves the same — ^F in voice 2 leaves voice 1 alone")
    func accidentalDoesNotLeakBackward() {
        let result = parse(Self.twoVoiceHeader + "[V:2] ^F F [V:1] F F|\n")
        let one = voiceMeasures(result, "1").first?.noteEvents ?? []
        let two = voiceMeasures(result, "2").first?.noteEvents ?? []
        guard one.count >= 2, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(two[0].pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(two[1].pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(one[0].pitch.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(one[0].displayedAccidental == nil)
        #expect(one[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("Bar reset is independent per voice")
    func barResetIsPerVoice() {
        // Voice 1 leaves its bar open across the voice switch; voice 2 then closes a bar of
        // its own. That bar line is voice 2's, so voice 1's ^F must survive it — all four of
        // voice 1's notes are one bar and all four sound F#.
        let result = parse(Self.twoVoiceHeader + "[V:1] ^F F\n[V:2] F F|\n[V:1] F F|\n")
        let one = voiceMeasures(result, "1").first?.noteEvents ?? []
        let two = voiceMeasures(result, "2").first?.noteEvents ?? []
        guard one.count >= 4, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let sharp = Alteration(numerator: 1, denominator: 1)
        #expect(one.prefix(4).allSatisfy { $0.pitch.alteration == sharp })
        // …and voice 2, which never wrote one, stays natural throughout.
        #expect(two.allSatisfy { $0.pitch.alteration == Alteration(numerator: 0, denominator: 1) })
    }

    @Test("A voice line that ends mid-bar keeps its accidental to itself")
    func accidentalDoesNotLeakAcrossAVoiceLineBreak() {
        // Whole V: lines rather than inline [V:…], neither ending on a bar line.
        let result = parse("X:1\nT:T\nM:4/4\nL:1/4\nK:C\nV:1\nV:2\nV:1\n^F F\nV:2\nF F\n")
        let two = voiceMeasures(result, "2").first?.noteEvents ?? []
        guard two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(two[0].pitch.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(two[0].displayedAccidental == nil)
        #expect(two[1].pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("An inline [K:] re-seeds only the voice that wrote it")
    func keyChangeRekeysOnlyItsOwnVoice() {
        // §7.3: a field that sets a music property should be repeated in every voice it
        // applies to — so voice 1's [K:G] moves voice 1 and leaves voice 2 in C.
        let result = parse(Self.twoVoiceHeader + "[V:1] F [K:G] F [V:2] F F|\n")
        let one = voiceMeasures(result, "1").first?.noteEvents ?? []
        let two = voiceMeasures(result, "2").first?.noteEvents ?? []
        guard one.count >= 2, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let sharp = Alteration(numerator: 1, denominator: 1)
        let natural = Alteration(numerator: 0, denominator: 1)
        // Voice 1: natural before the change, sharpened by G major after it.
        #expect(one[0].pitch.alteration == natural)
        #expect(one[1].pitch.alteration == sharp)
        #expect(one[1].displayedAccidental == nil)
        // Voice 2 never wrote a K: and stays in the tune's C major.
        #expect(two.allSatisfy { $0.pitch.alteration == natural })
        #expect(two.allSatisfy { $0.displayedAccidental == nil })
    }
}
