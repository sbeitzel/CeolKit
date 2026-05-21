// Key signature parsing conformance tests. ABC §3.1.14.
import Testing
import CeolKitModel
import CeolKitParser

private func keyTune(_ kField: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\n\(kField)\nC|"
}

@Suite("Key Signatures")
struct KeySignatureTests {

    // MARK: Major keys

    @Test("K:C is C major with natural tonic")
    func cMajor() {
        let result = parse(keyTune("K:C"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .c)
        #expect(key?.tonic?.alteration == Alteration(numerator: 0, denominator: 1))
        #expect(key?.mode == .major)
    }

    @Test("K:G is G major with natural tonic")
    func gMajor() {
        let result = parse(keyTune("K:G"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .g)
        #expect(key?.mode == .major)
    }

    @Test("K:D is D major with natural tonic")
    func dMajor() {
        let result = parse(keyTune("K:D"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .d)
        #expect(key?.mode == .major)
    }

    @Test("K:F is F major with natural tonic")
    func fMajor() {
        let result = parse(keyTune("K:F"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .f)
        #expect(key?.mode == .major)
    }

    @Test("K:Bb is Bb major (flat tonic)")
    func bbMajor() {
        let result = parse(keyTune("K:Bb"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .b)
        #expect(key?.tonic?.alteration == Alteration(numerator: -1, denominator: 1))
        #expect(key?.mode == .major)
    }

    @Test("K:F# is F-sharp major (sharp tonic)")
    func fSharpMajor() {
        let result = parse(keyTune("K:F#"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .f)
        #expect(key?.tonic?.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(key?.mode == .major)
    }

    @Test("K:Eb is Eb major")
    func ebMajor() {
        let result = parse(keyTune("K:Eb"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .e)
        #expect(key?.tonic?.alteration == Alteration(numerator: -1, denominator: 1))
        #expect(key?.mode == .major)
    }

    // MARK: Minor keys

    @Test("K:Am is A minor")
    func aMinor() {
        let result = parse(keyTune("K:Am"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .a)
        #expect(key?.mode == .minor)
    }

    @Test("K:Dm is D minor")
    func dMinor() {
        let result = parse(keyTune("K:Dm"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .d)
        #expect(key?.mode == .minor)
    }

    @Test("K:Gm is G minor")
    func gMinor() {
        let result = parse(keyTune("K:Gm"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .g)
        #expect(key?.mode == .minor)
    }

    // MARK: Church modes

    @Test("K:Dmin is D minor (full word)")
    func dMinorFull() {
        let result = parse(keyTune("K:Dmin"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .d)
        #expect(key?.mode == .minor)
    }

    @Test("K:D Dor is D Dorian")
    func dDorian() {
        let result = parse(keyTune("K:D Dor"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .d)
        #expect(key?.mode == .dorian)
    }

    @Test("K:E Phr is E Phrygian")
    func ePhrygian() {
        let result = parse(keyTune("K:E Phr"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .e)
        #expect(key?.mode == .phrygian)
    }

    @Test("K:F Lyd is F Lydian")
    func fLydian() {
        let result = parse(keyTune("K:F Lyd"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .f)
        #expect(key?.mode == .lydian)
    }

    @Test("K:G Mix is G Mixolydian")
    func gMixolydian() {
        let result = parse(keyTune("K:G Mix"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .g)
        #expect(key?.mode == .mixolydian)
    }

    @Test("K:A Aeo is A Aeolian")
    func aAeolian() {
        let result = parse(keyTune("K:A Aeo"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .a)
        #expect(key?.mode == .aeolian)
    }

    @Test("K:B Loc is B Locrian")
    func bLocrian() {
        let result = parse(keyTune("K:B Loc"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .b)
        #expect(key?.mode == .locrian)
    }

    // MARK: Special keys

    @Test("K:none produces no-key-signature mode")
    func keyNone() {
        let result = parse(keyTune("K:none"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic == nil)
        #expect(key?.mode == Mode.none)
    }

    @Test("K:HP is highland pipes key (F# and C# implicit)")
    func keyHP() {
        let result = parse(keyTune("K:HP"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic == nil)
        #expect(key?.mode == .highlandPipes)
    }

    @Test("K:Hp is highland pipes no-signature mode")
    func keyHp() {
        let result = parse(keyTune("K:Hp"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic == nil)
        #expect(key?.mode == .highlandPipesNoSignature)
    }

    // MARK: Key with modifications

    @Test("K:D Phr ^f adds f-sharp modification to D Phrygian")
    func keyWithModification() {
        let result = parse(keyTune("K:D Phr ^f"))
        let key = result.score.firstTune?.key
        #expect(key?.tonic?.step == .d)
        #expect(key?.mode == .phrygian)
        let mods = key?.modifications ?? []
        #expect(!mods.isEmpty)
        let fMod = mods.first(where: { $0.step == .f })
        #expect(fMod?.alteration == Alteration(numerator: 1, denominator: 1))
    }

    // MARK: Clef in key

    @Test("K:G clef=bass sets bass clef")
    func keyWithBassClef() {
        let result = parse(keyTune("K:G clef=bass"))
        let key = result.score.firstTune?.key
        #expect(key?.clef.clef == .bass)
    }

    @Test("K:C treble+8 sets treble clef with +8 octave shift")
    func keyWithTreblePlus8() {
        let result = parse(keyTune("K:C treble+8"))
        let key = result.score.firstTune?.key
        #expect(key?.clef.clef == .treble)
        #expect(key?.clef.octaveShift == 8)
    }

    // MARK: Explicit accidentals in key (K: ... exp ...)

    @Test("K:D exp ^f _e marks key as using explicit accidentals")
    func keyExplicit() {
        let result = parse(keyTune("K:D exp ^f _e"))
        let key = result.score.firstTune?.key
        #expect(key?.explicit == true)
    }

    // MARK: Mid-tune key change

    @Test("Mid-tune K:G after K:D updates subsequent notes")
    func midTuneKeyChange() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:D
        FDAF|
        K:G
        FDAG|
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        let measures = tune?.singleVoiceMeasures ?? []
        guard measures.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // In D major, F has a sharp in the key (F#)
        let firstF = measures[0].noteEvents.first
        #expect(firstF?.pitch.step == .f)
        #expect(firstF?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
        // In G major, F also has a sharp — same pitch alteration
        let secondF = measures[1].noteEvents.first
        #expect(secondF?.pitch.step == .f)
        #expect(secondF?.pitch.alteration == Alteration(numerator: 1, denominator: 1))
    }
}
