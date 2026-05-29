// Pitch, octave, and accidental parsing conformance tests.
// ABC convention: uppercase C..B = octave 4 (C = middle C = C4), lowercase c..b = octave 5;
// ' raises by one octave, , lowers by one octave.
import Testing
import CeolKitModel
import CeolKitParser

private func singleNoteTune(_ noteStr: String, key: String = "K:C") -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\n\(key)\n\(noteStr)|"
}

@Suite("Pitch and Octave")
struct PitchTests {

    // MARK: Octave from letter case (K:C, no accidentals in key)

    @Test("Uppercase C is octave 4 (middle C)")
    func uppercaseCIsOctave4() {
        let result = parse(singleNoteTune("C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 4)
    }

    @Test("Lowercase c is octave 5")
    func lowercaseCIsOctave5() {
        let result = parse(singleNoteTune("c"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 5)
    }

    @Test("Uppercase G is octave 4")
    func uppercaseGIsOctave4() {
        let result = parse(singleNoteTune("G"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .g)
        #expect(note?.pitch.octave == 4)
    }

    @Test("Lowercase g is octave 5")
    func lowercaseGIsOctave5() {
        let result = parse(singleNoteTune("g"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .g)
        #expect(note?.pitch.octave == 5)
    }

    @Test("Uppercase B is octave 4")
    func uppercaseBIsOctave4() {
        let result = parse(singleNoteTune("B"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .b)
        #expect(note?.pitch.octave == 4)
    }

    // MARK: Octave marks

    @Test("c' is octave 6")
    func cPrimeIsOctave6() {
        let result = parse(singleNoteTune("c'"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 6)
    }

    @Test("c'' is octave 7")
    func cDoublePrimeIsOctave7() {
        let result = parse(singleNoteTune("c''"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 7)
    }

    @Test("C, is octave 3")
    func cCommaIsOctave3() {
        let result = parse(singleNoteTune("C,"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 3)
    }

    @Test("C,, is octave 2")
    func cDoubleCommaIsOctave2() {
        let result = parse(singleNoteTune("C,,"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .c)
        #expect(note?.pitch.octave == 2)
    }

    @Test("G, is octave 3")
    func gCommaIsOctave3() {
        let result = parse(singleNoteTune("G,"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .g)
        #expect(note?.pitch.octave == 3)
    }

    // MARK: Diatonic steps

    @Test("All seven diatonic steps parse correctly (C D E F G A B)")
    func allDiatonicSteps() {
        let expected: [(String, DiatonicStep)] = [
            ("C", .c), ("D", .d), ("E", .e), ("F", .f),
            ("G", .g), ("A", .a), ("B", .b)
        ]
        for (letter, step) in expected {
            let result = parse(singleNoteTune(letter))
            let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
            #expect(note?.pitch.step == step, "Letter \(letter) should map to step \(step)")
        }
    }

    // MARK: Written accidentals

    @Test("^C produces sharp: writtenAccidental = +1/1")
    func sharpAccidental() {
        let result = parse(singleNoteTune("^C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 1, denominator: 1))
        #expect(note?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
    }

    @Test("_C produces flat: writtenAccidental = -1/1")
    func flatAccidental() {
        let result = parse(singleNoteTune("_C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: -1, denominator: 1))
        #expect(note?.pitch.alteration == Alteration(numerator: -1, denominator: 1))
    }

    @Test("^^C produces double-sharp: writtenAccidental = +2/1")
    func doubleSharpAccidental() {
        let result = parse(singleNoteTune("^^C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 2, denominator: 1))
    }

    @Test("__C produces double-flat: writtenAccidental = -2/1")
    func doubleFlatAccidental() {
        let result = parse(singleNoteTune("__C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: -2, denominator: 1))
    }

    @Test("=C produces natural: writtenAccidental = 0/1")
    func naturalAccidental() {
        let result = parse(singleNoteTune("=C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 0, denominator: 1))
    }

    // MARK: Microtonal accidentals

    @Test("^1/2C produces quarter-sharp: writtenAccidental = +1/2")
    func quarterSharp() {
        let result = parse(singleNoteTune("^1/2C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 1, denominator: 2))
    }

    @Test("_1/2C produces quarter-flat: writtenAccidental = -1/2")
    func quarterFlat() {
        let result = parse(singleNoteTune("_1/2C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: -1, denominator: 2))
    }

    @Test("^3/2C produces three-quarter-sharp: writtenAccidental = +3/2")
    func threeQuarterSharp() {
        let result = parse(singleNoteTune("^3/2C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.writtenAccidental == Alteration(numerator: 3, denominator: 2))
    }

    @Test("Microtonal fraction is always reduced: ^2/4C → +1/2")
    func microtonalFractionReduced() {
        let result = parse(singleNoteTune("^2/4C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        // 2/4 must be reduced to 1/2
        #expect(note?.writtenAccidental == Alteration(numerator: 1, denominator: 2))
    }

    // MARK: Key signature affects pitch.alteration

    @Test("F in K:G has pitch alteration +1/1 (sharp from key signature)")
    func fInGMajorIsSharp() {
        let result = parse(singleNoteTune("F", key: "K:G"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.pitch.step == .f)
        #expect(note?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
        // writtenAccidental is nil: the sharp comes from the key, not a written sign
        #expect(note?.writtenAccidental == nil)
        // displayedAccidental is also nil: key signature handles the display
        #expect(note?.displayedAccidental == nil)
    }
}
