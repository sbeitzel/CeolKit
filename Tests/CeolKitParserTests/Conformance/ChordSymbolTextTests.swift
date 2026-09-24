// Unprefixed quoted text that is not a chord symbol. ABC §4.18.
//
// Issue #177: `"repeat of part 2"A` was read as a chord symbol, failed to parse as one, and
// was dropped; `"Fine"A` parsed as an F chord of quality "ine".  §4.18 asks for chord symbols
// to be treated "quite liberally", and abcm2ps prints such text as written on the chord line.
import Testing
import CeolKitModel
import CeolKitParser

private func chordTune(_ body: String) -> String {
    "X:1\nT:Test\nM:6/8\nL:1/8\nK:D\n\(body)|]"
}

@Suite("Unprefixed text that is not a chord symbol")
struct ChordSymbolTextTests {

    private func firstNote(_ body: String) throws -> (note: Note, result: ParseResult) {
        let result = parse(chordTune(body))
        let measure = try #require(result.score.firstTune?.singleVoiceMeasures.first)
        return (try #require(measure.noteEvents.first), result)
    }

    @Test("\"repeat of part 2\"A keeps the text on A, as chord-line text and not a chord")
    func freeTextIsKeptOnTheNote() throws {
        let (note, _) = try firstNote(#""repeat of part 2"A>ee e2 d"#)
        #expect(note.chordSymbol == nil)
        let text = try #require(note.annotations.first)
        #expect(note.annotations.count == 1)
        #expect(text.position == .chordLine)
        #expect(text.text.value == "repeat of part 2")
    }

    @Test("\"Fine\" is text, not an F chord of quality \"ine\"")
    func fineIsNotAChord() throws {
        let (note, _) = try firstNote(#""Fine"A>ee e2 d"#)
        #expect(note.chordSymbol == nil)
        #expect(note.annotations.map(\.position) == [.chordLine])
        #expect(note.annotations.map(\.text.value) == ["Fine"])
    }

    @Test("A warning points at the string and suggests \"^…\"")
    func warningPointsAtTheString() throws {
        let source = chordTune(#""repeat of part 2"A>ee e2 d"#)
        let result = parse(source)
        let warnings = result.score.warningDiagnostics.filter { $0.code == .unrecognisedChordSymbol }
        let warning = try #require(warnings.first)
        #expect(warnings.count == 1)
        #expect(warning.message.contains("^repeat of part 2"))
        let quoted = try #require(source.utf8.firstIndex(of: UInt8(ascii: "\"")))
        let offset = source.utf8.distance(from: source.utf8.startIndex, to: quoted)
        #expect(warning.source.byteOffset >= offset)
        #expect(warning.source.byteOffset <= offset + 1)
    }

    @Test("Chord symbols read as before, with no warning",
          arguments: ["G", "Am7", "Bbmaj7", "F#m7b5", "C/E", "Dm/f", "G7sus4", "Cadd9", "E-",
                      "Bdim", "C+", "Co7", "Cø", "Eb", "D♯m", "G(Em)", "Am7(b5)", "A"])
    func chordSymbolsStillParse(_ spelling: String) throws {
        let (note, result) = try firstNote("\"\(spelling)\"A>ee e2 d")
        let symbol = try #require(note.chordSymbol)
        #expect(symbol.raw == spelling)
        #expect(note.annotations.isEmpty)
        #expect(!result.score.diagnostics.contains { $0.code == .unrecognisedChordSymbol })
    }

    @Test("The parts of a chord are still read for transposition")
    func chordPartsAreRead() throws {
        let (note, _) = try firstNote(#""F#m7/C#"A>ee e2 d"#)
        let symbol = try #require(note.chordSymbol)
        #expect(symbol.root == PitchClass(step: .f, alteration: .sharp))
        #expect(symbol.quality == "m7")
        #expect(symbol.bassNote == PitchClass(step: .c, alteration: .sharp))
    }

    @Test("An alternate chord is kept in raw but not in the quality")
    func alternateChordIsForPrintingOnly() throws {
        let (note, _) = try firstNote(#""G(Em)"A>ee e2 d"#)
        let symbol = try #require(note.chordSymbol)
        #expect(symbol.root == PitchClass(step: .g, alteration: .natural))
        #expect(symbol.quality == "")
        #expect(symbol.raw == "G(Em)")
    }

    @Test("Text that only starts like a chord is text",
          arguments: ["Fine", "Coda", "D.C. al Fine", "Dal Segno", "A part", "C/", "N.C."])
    func lookalikesAreText(_ text: String) throws {
        let (note, _) = try firstNote("\"\(text)\"A>ee e2 d")
        #expect(note.chordSymbol == nil)
        #expect(note.annotations.map(\.text.value) == [text])
    }

    /// svpb-music's `Bengullion.abc`: the text also stands before a grace group (#176).
    @Test("[2 \"repeat of part 2\"{g}A puts the text on A")
    func freeTextBeforeGraceInEnding() throws {
        let result = parse(chordTune(#"|:A>ee e2 d|1 A>ee e2 d:|[2 "repeat of part 2"{g}A>ee e2 d"#))
        let notes = result.score.firstTune?.singleVoiceMeasures.flatMap(\.noteEvents) ?? []
        let texts = notes.flatMap(\.annotations).map(\.text.value)
        #expect(texts == ["repeat of part 2"])
        let graces = result.score.firstTune?.singleVoiceMeasures.flatMap(\.graceEvents) ?? []
        #expect(graces.flatMap(\.notes).allSatisfy { $0.annotations.isEmpty })
    }

    @Test("A chord symbol and free text on one note are both kept")
    func chordAndTextTogether() throws {
        let (note, _) = try firstNote(#""G""Fine"A>ee e2 d"#)
        #expect(note.chordSymbol?.raw == "G")
        #expect(note.annotations.map(\.text.value) == ["Fine"])
    }
}
