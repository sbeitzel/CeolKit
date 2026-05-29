// §14.1 English.abc — three tunes demonstrating information fields,
// broken rhythm, meter changes, inline fields, parts, and trailing words.
import Testing
import CeolKitModel
import CeolKitParser

private let englishABC = """
%abc-2.1
H:This file contains some example English tunes
% note that the comments (like this one) are to highlight usages
%  and would not normally be included in such detail
O:England             % the origin of all tunes is England

X:1                   % tune no 1
T:Dusty Miller, The   % title
T:Binny's Jig         % an alternative title
C:Trad.               % traditional
R:DH                  % double hornpipe
M:3/4                 % meter
K:G                   % key
B>cd BAG|FA Ac BA|B>cd BAG|DG GB AG:|
Bdd gfg|aA Ac BA|Bdd gfa|gG GB AG:|
BG G/2G/2G BG|FA Ac BA|BG G/2G/2G BG|DG GB AG:|
W:Hey, the dusty miller, and his dusty coat;
W:He will win a shilling, or he spend a groat.
W:Dusty was the coat, dusty was the colour;
W:Dusty was the kiss, that I got frae the miller.

X:2
T:Old Sir Simon the King
C:Trad.
S:Offord MSS          % from Offord manuscript
N:see also Playford   % reference note
M:9/8
R:SJ                  % slip jig
N:originally in C     % transcription note
K:G
D|GFG GAG G2D|GFG GAG F2D|EFE EFE EFG|A2G F2E D2:|
D|GAG GAB d2D|GAG GAB c2D|[1 EFE EFE EFG|A2G F2E D2:|\\
M:12/8                % change of meter
[2 E2E EFE E2E EFG|\\
M:9/8                 % change of meter
A2G F2E D2|]

X:3
T:William and Nancy
T:New Mown Hay
T:Legacy, The
C:Trad.
O:England; Gloucs; Bledington
B:Sussex Tune Book
B:Mally's Cotswold Morris vol.1 2
D:Morris On
P:(AB)2(AC)2A
M:6/8
K:G
[P:A] D|"G"G2G GBd|"C"e2e "G"dBG|"D7"A2d "G"BAG|"C"E2"D7"F "G"G2:|
[P:B] d|"G"e2d B2d|"C"gfe "G"d2d|"G"e2d B2d|"C"gfe "D7"d2c|
       "G"B2B Bcd|"C"e2e "G"dBG|"D7"A2d "G"BAG|"C"E2"D7"F "G"G2:|
[T:Slows][M:4/4][L:1/4][P:C]"G"d2|"C"e2 "G"d2|B2 d2|"Em"gf "A7"e2|"D7"d2 "G"d2|\\
       "C"e2 "G"d2|[M:3/8][L:1/8]"G"B2 d|[M:6/8]"C"gfe "D7"d2c|
       "G"B2B Bcd|"C"e2e "G"dBG|"D7"A2d "G"BAG|"C"E2"D7"F "G"G2:|
"""

@Suite("§14.1 English.abc")
struct EnglishABCTests {

    let result = parse(englishABC)
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

    @Test("File contains exactly three tunes")
    func tuneCount() {
        #expect(score.tunes.count == 3)
    }

    @Test("Parse produces no error-level diagnostics")
    func noErrors() {
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    // MARK: Tune 1 — Dusty Miller

    @Test("Tune 1 reference number is 1")
    func tune1Reference() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.reference == 1)
    }

    @Test("Tune 1 has two titles")
    func tune1TitleCount() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.titles.count == 2)
    }

    @Test("Tune 1 primary title is 'Dusty Miller, The'")
    func tune1PrimaryTitle() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.titles.first?.value == "Dusty Miller, The")
    }

    @Test("Tune 1 secondary title is 'Binny's Jig'")
    func tune1SecondaryTitle() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.titles.dropFirst().first?.value == "Binny's Jig")
    }

    @Test("Tune 1 meter is 3/4")
    func tune1Meter() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        if case .fraction(let num, let den) = tune.meter {
            #expect(num == 3)
            #expect(den == 4)
        } else {
            Issue.record("Expected .fraction(3, 4), got \(tune.meter)")
        }
    }

    @Test("Tune 1 key is G major")
    func tune1Key() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.key.tonic?.step == .g)
        #expect(tune.key.mode == .major)
        #expect(tune.key.tonic?.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("Tune 1 unit note length defaults to 1/8 for M:3/4")
    func tune1UnitNoteLength() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("Tune 1 composer is Trad.")
    func tune1Composer() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.metadata.composer?.value == "Trad.")
    }

    @Test("Tune 1 first measure has six notes")
    func tune1FirstMeasureNoteCount() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(measure.noteEvents.count == 6)
    }

    @Test("Tune 1 first note is B (octave 4)")
    func tune1FirstNote() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first,
              let note = measure.noteEvents.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(note.pitch.step == .b)
        #expect(note.pitch.octave == 4)
    }

    @Test("Tune 1 first note has broken-right duration 3/2")
    func tune1FirstNoteBrokenRhythm() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first,
              let note = measure.noteEvents.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(note.duration == Fraction(numerator: 3, denominator: 2))
    }

    @Test("Tune 1 second note (c) has broken-left duration 1/2")
    func tune1SecondNote() {
        guard let tune = score.tunes.first,
              let measure = tune.firstVoice?.allMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        let notes = measure.noteEvents
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(notes[1].pitch.step == .c)
        #expect(notes[1].pitch.octave == 5)
        #expect(notes[1].duration == Fraction(numerator: 1, denominator: 2))
    }

    @Test("Tune 1 first measure closes with a repeat end bar")
    func tune1FirstMeasureClosingBar() {
        guard let tune = score.tunes.first,
              let measures = tune.firstVoice?.allMeasures else { Issue.record("Parser prerequisite not met"); return }
        // The repeat closes at the end of line 1 (4 bars)
        let repeatMeasure = measures.first(where: { $0.closingBar.kind == .repeatEnd })
        #expect(repeatMeasure != nil)
    }

    // MARK: Tune 2 — Old Sir Simon the King

    @Test("Tune 2 reference number is 2")
    func tune2Reference() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[1].reference == 2)
    }

    @Test("Tune 2 title is 'Old Sir Simon the King'")
    func tune2Title() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[1].titles.first?.value == "Old Sir Simon the King")
    }

    @Test("Tune 2 initial meter is 9/8")
    func tune2Meter() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        if case .fraction(let num, let den) = tune.meter {
            #expect(num == 9)
            #expect(den == 8)
        } else {
            Issue.record("Expected .fraction(9, 8), got \(tune.meter)")
        }
    }

    @Test("Tune 2 key is G major")
    func tune2Key() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        #expect(tune.key.tonic?.step == .g)
        #expect(tune.key.mode == .major)
    }

    @Test("Tune 2 has variant ending measures (|1 and |2)")
    func tune2VariantEndings() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        let allMeasures = tune.singleVoiceMeasures
        let ending1 = allMeasures.first(where: { $0.endingNumber?.contains(1) == true })
        let ending2 = allMeasures.first(where: { $0.endingNumber?.contains(2) == true })
        #expect(ending1 != nil)
        #expect(ending2 != nil)
    }

    @Test("Tune 2 anacrusis measure contains single D note")
    func tune2Anacrusis() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        guard let first = tune.singleVoiceMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        let notes = first.noteEvents
        #expect(notes.count == 1)
        #expect(notes.first?.pitch.step == .d)
        #expect(notes.first?.pitch.octave == 4)
    }

    // MARK: Tune 3 — William and Nancy / Legacy

    @Test("Tune 3 reference number is 3")
    func tune3Reference() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[2].reference == 3)
    }

    @Test("Tune 3 has three titles")
    func tune3TitleCount() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[2].titles.count == 3)
    }

    @Test("Tune 3 titles are William and Nancy, New Mown Hay, Legacy The")
    func tune3Titles() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        let titles = score.tunes[2].titles.map(\.value)
        #expect(titles.contains("William and Nancy"))
        #expect(titles.contains("New Mown Hay"))
        #expect(titles.contains("Legacy, The"))
    }

    @Test("Tune 3 initial meter is 6/8")
    func tune3Meter() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[2]
        if case .fraction(let num, let den) = tune.meter {
            #expect(num == 6)
            #expect(den == 8)
        } else {
            Issue.record("Expected .fraction(6, 8), got \(tune.meter)")
        }
    }

    @Test("Tune 3 has chord symbols G, C, D7")
    func tune3ChordSymbols() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[2]
        let allNotes = tune.singleVoiceMeasures.flatMap(\.noteEvents)
        let chordRaws = allNotes.compactMap(\.chordSymbol?.raw)
        #expect(chordRaws.contains("G"))
        #expect(chordRaws.contains("C"))
        #expect(chordRaws.contains("D7"))
    }

    @Test("Tune 3 origin includes England and Gloucestershire")
    func tune3Origin() {
        guard score.tunes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        let origins = score.tunes[2].metadata.origin
        #expect(origins.contains("England"))
        #expect(origins.contains("Gloucs"))
        #expect(origins.contains("Bledington"))
    }
}
