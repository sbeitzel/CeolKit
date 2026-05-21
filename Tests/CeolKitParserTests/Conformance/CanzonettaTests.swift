// §14.4 Canzonetta.abc — Monteverdi piece demonstrating three voices,
// stylesheet directives, tempo, Eb major, lyrics, decorations, and variant endings.
import Testing
import CeolKitModel
import CeolKitParser

private let canzonettaABC = """
%abc-2.1
%%pagewidth      21cm
%%pageheight     29.7cm
%%topspace       0.5cm
%%topmargin      1cm
%%botmargin      0cm
%%leftmargin     1cm
%%rightmargin    1cm
%%titlespace     0cm
%%titlefont      Times-Bold 32
%%subtitlefont   Times-Bold 24
%%composerfont   Times 16
%%vocalfont      Times-Roman 14
%%staffsep       60pt
%%sysstaffsep    20pt
%%musicspace     1cm
%%vocalspace     5pt
%%measurenb      0
%%barsperstaff   5
%%scale          0.7
X: 1
T: Canzonetta a tre voci
C: Claudio Monteverdi (1567-1643)
M: C
L: 1/4
Q: "Andante mosso" 1/4 = 110
%%score [1 2 3]
V: 1 clef=treble name="Soprano" sname="A"
V: 2 clef=treble name="Alto"    sname="T"
V: 3 clef=bass   name="Tenor"   sname="B" octave=-2
%%MIDI program 1 75
%%MIDI program 2 75
%%MIDI program 3 75
K: Eb
% 1 - 4
[V: 1] |:z4  |z4  |f2ec         |_ddcc        |
w: Son que-sti~i cre-spi cri-ni~e
w: Que-sti son gli~oc-chi che mi-
[V: 2] |:c2BG|AAGc|(F/G/A/B/)c=A|B2AA         |
w: Son que-sti~i cre-spi cri-ni~e que - - - - sto~il vi-so e
w: Que-sti son~gli oc-chi che mi-ran - - - - do fi-so mi-
[V: 3] |:z4  |f2ec|_ddcf        |(B/c/_d/e/)ff|
w: Son que-sti~i cre-spi cri-ni~e que - - - - sto~il
w: Que-sti son~gli oc-chi che mi-ran - - - - do
% 5 - 9
[V: 1] cAB2     |cAAA |c3B|G2!fermata!Gz ::e4|
w: que-sto~il vi-so ond' io ri-man-go~uc-ci-so. Deh,
w: ran-do fi-so, tut-to re-stai con-qui-so.
[V: 2] AAG2     |AFFF |A3F|=E2!fermata!Ez::c4|
w: que-sto~il vi-so ond' io ri-man-go~uc-ci-so. Deh,
w: ran-do fi-so tut-to re-stai con-qui-so.
[V: 3] (ag/f/e2)|A_ddd|A3B|c2!fermata!cz ::A4|
w: vi - - - so ond' io ti-man-go~uc-ci-so. Deh,
w: fi - - - so tut-to re-stai con-qui-so.
% 10 - 15
[V: 1] f_dec |B2c2|zAGF  |\\
w: dim-me-lo ben mi-o, che que-sto\\
=EFG2          |1F2z2:|2F8|]
w: sol de-si-o_.
[V: 2] ABGA  |G2AA|GF=EF |(GF3/2=E//D//E)|1F2z2:|2F8|]
w: dim-me-lo ben mi-o, che que-sto sol de-si - - - - o_.
[V: 3] _dBc>d|e2AF|=EFc_d|c4             |1F2z2:|2F8|]
w: dim-me-lo ben mi-o, che que-sto sol de-si-o_.
"""

@Suite("§14.4 Canzonetta.abc")
struct CanzonettaTests {

    let result = parse(canzonettaABC)
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

    @Test("File contains exactly one tune")
    func tuneCount() {
        #expect(score.tunes.count == 1)
    }

    @Test("Parse produces no error diagnostics")
    func noErrors() {
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    // MARK: Header fields

    @Test("Tune title is 'Canzonetta a tre voci'")
    func tuneTitle() {
        #expect(score.firstTune?.titles.first?.value == "Canzonetta a tre voci")
    }

    @Test("Composer is Claudio Monteverdi (1567-1643)")
    func tuneComposer() {
        #expect(score.firstTune?.metadata.composer?.value == "Claudio Monteverdi (1567-1643)")
    }

    @Test("Meter is common time (C)")
    func tuneMeter() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        if case .commonTime = tune.meter {
            // expected
        } else {
            Issue.record("Expected .commonTime, got \(tune.meter)")
        }
    }

    @Test("Unit note length is 1/4")
    func tuneUnitLength() {
        #expect(score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 4))
    }

    @Test("Tempo is 110 bpm with quarter-note beat")
    func tuneTempo() {
        guard let tempo = score.firstTune?.tempo else {
            Issue.record("No tempo found")
            return
        }
        #expect(tempo.bpm == 110.0)
        #expect(tempo.beats == [Fraction(numerator: 1, denominator: 4)])
    }

    @Test("Tempo prelude text is 'Andante mosso'")
    func tuneTempoText() {
        #expect(score.firstTune?.tempo?.prelude?.value == "Andante mosso")
    }

    @Test("Key is Eb major")
    func tuneKey() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.key.tonic?.step == .e)
        #expect(tune.key.tonic?.alteration == Alteration(numerator: -1, denominator: 1))
        #expect(tune.key.mode == .major)
    }

    // MARK: Multi-voice

    @Test("Tune has exactly three voices")
    func voiceCount() {
        #expect(score.firstTune?.voices.count == 3)
    }

    @Test("Voice 1 id is '1'")
    func voice1Id() {
        guard let voices = score.firstTune?.voices, !voices.isEmpty else { Issue.record("Parser prerequisite not met"); return }
        if case .named(let name) = voices[0].id {
            #expect(name == "1")
        } else {
            Issue.record("Expected .named(\"1\"), got \(voices[0].id)")
        }
    }

    @Test("Voice 1 clef is treble")
    func voice1Clef() {
        guard let voices = score.firstTune?.voices, !voices.isEmpty else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[0].properties.clef.clef == .treble)
    }

    @Test("Voice 1 name is Soprano")
    func voice1Name() {
        guard let voices = score.firstTune?.voices, !voices.isEmpty else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[0].properties.name == "Soprano")
    }

    @Test("Voice 2 clef is treble")
    func voice2Clef() {
        guard let voices = score.firstTune?.voices, voices.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[1].properties.clef.clef == .treble)
    }

    @Test("Voice 2 name is Alto")
    func voice2Name() {
        guard let voices = score.firstTune?.voices, voices.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[1].properties.name == "Alto")
    }

    @Test("Voice 3 clef is bass")
    func voice3Clef() {
        guard let voices = score.firstTune?.voices, voices.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[2].properties.clef.clef == .bass)
    }

    @Test("Voice 3 name is Tenor")
    func voice3Name() {
        guard let voices = score.firstTune?.voices, voices.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[2].properties.name == "Tenor")
    }

    @Test("Voice 3 has octave=-2 transposition")
    func voice3Transposition() {
        guard let voices = score.firstTune?.voices, voices.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(voices[2].properties.transposition.octave == -2)
    }

    // MARK: Musical content

    @Test("Voice 1 first measure begins with a rest")
    func voice1FirstMeasureStartsWithRest() {
        guard let tune = score.firstTune,
              let voice1 = tune.voices.first,
              let firstMeasure = voice1.firstMeasure else { Issue.record("Parser prerequisite not met"); return }
        // After the opening repeat bar |:, the first event should be a rest (z4)
        let rests = firstMeasure.restEvents
        #expect(!rests.isEmpty)
    }

    @Test("Voice 1 has a fermata decoration in the score")
    func voice1HasFermata() {
        guard let tune = score.firstTune,
              let voice1 = tune.voices.first else { Issue.record("Parser prerequisite not met"); return }
        let allNotes = voice1.allMeasures.flatMap(\.noteEvents)
        let hasFermata = allNotes.contains { $0.decorations.contains(.fermata) }
        #expect(hasFermata)
    }

    @Test("All three voices have lyrics")
    func allVoicesHaveLyrics() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        for voice in tune.voices {
            let notesWithLyrics = voice.allMeasures.flatMap(\.noteEvents).filter { $0.lyric != nil }
            #expect(!notesWithLyrics.isEmpty, "Voice \(voice.id) has no lyrics")
        }
    }

    @Test("Tune has variant endings |1 and |2")
    func tuneHasVariantEndings() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        for voice in tune.voices {
            let measures = voice.allMeasures
            let ending1 = measures.first(where: { $0.endingNumber?.contains(1) == true })
            let ending2 = measures.first(where: { $0.endingNumber?.contains(2) == true })
            #expect(ending1 != nil, "Voice \(voice.id) missing ending 1")
            #expect(ending2 != nil, "Voice \(voice.id) missing ending 2")
        }
    }

    @Test("Tune has repeat-both bar (::) between sections")
    func tuneHasRepeatBoth() {
        guard let tune = score.firstTune else { Issue.record("Parser prerequisite not met"); return }
        let hasRepeatBoth = tune.voices.contains { voice in
            voice.allMeasures.contains { $0.closingBar.kind == .repeatBoth }
        }
        #expect(hasRepeatBoth)
    }

    @Test("Voice 2 contains a natural sign (=E in K:Eb context)")
    func voice2NaturalSign() {
        guard let tune = score.firstTune,
              tune.voices.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let voice2 = tune.voices[1]
        let allNotes = voice2.allMeasures.flatMap(\.noteEvents)
        // =E in K:Eb means a natural E; writtenAccidental should be .natural
        let hasNatural = allNotes.contains {
            $0.writtenAccidental == Alteration(numerator: 0, denominator: 1) &&
            $0.pitch.step == .e
        }
        #expect(hasNatural)
    }
}
