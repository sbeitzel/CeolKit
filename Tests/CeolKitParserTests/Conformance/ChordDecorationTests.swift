// Decorations written inside a chord's brackets (ABC §4.14, §4.17; issue #266).
// abcm2ps reads a decoration in front of a note inside `[ … ]` as that note's.
import Testing
import CeolKitModel
import CeolKitParser

private func chordTune(_ body: String, preamble: String = "") -> String {
    "X:1\nT:Test\nM:4/4\nL:1/8\n\(preamble)K:D\n\(body)|]\n"
}

@Suite("Decorations inside chords (#266)")
struct ChordDecorationTests {

    @Test("[Tce] trills the c, the note the T is written on")
    func shortFormOnFirstNote() throws {
        let result = parse(chordTune("[Tce]2"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes[0].decorations == [.trill])
        #expect(chord.notes[1].decorations.isEmpty)
        #expect(chord.decorations.isEmpty)
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("[c!fermata!e] puts the fermata on the e")
    func longFormOnSecondNote() throws {
        let result = parse(chordTune("[c!fermata!e]2"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes[0].decorations.isEmpty)
        #expect(chord.notes[1].decorations == [.fermata])
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("A decoration before the bracket stays the chord's")
    func decorationBeforeBracket() throws {
        let result = parse(chordTune("T[ce]2"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        #expect(chord.decorations == [.trill])
        #expect(chord.notes.allSatisfy { $0.decorations.isEmpty })
    }

    @Test("Several decorations and an accidental in front of one note")
    func severalDecorationsAndAccidental() throws {
        let result = parse(chordTune("[c.!accent!=e]2"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes[1].decorations == [.staccato, .accent])
        #expect(chord.notes[1].writtenAccidental == Alteration(numerator: 0, denominator: 1))
    }

    @Test("A U: symbol inside the brackets expands as it does outside them")
    func userSymbol() throws {
        let result = parse(chordTune("[cWe]2", preamble: "U:W=!coda!\n"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes[1].decorations == [.coda])
        #expect(result.score.diagnostics.isEmpty)
    }

    @Test("An undefined symbol inside the brackets is reported and ignored")
    func undefinedSymbol() throws {
        let result = parse(chordTune("[cQe]2"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes.allSatisfy { $0.decorations.isEmpty })
        #expect(result.score.warningDiagnostics.map(\.code) == [.reservedCharacter])
    }

    @Test("A decoration after the last note is reported, and the chord keeps its notes")
    func trailingDecoration() throws {
        let result = parse(chordTune("[ce!fermata!]2 d2"))
        let measure = try #require(result.score.firstTune?.singleVoiceMeasures.first)
        let chord = try #require(measure.chordEvents.first)
        try #require(chord.notes.count == 2)
        #expect(chord.notes.allSatisfy { $0.decorations.isEmpty })
        #expect(chord.decorations.isEmpty)
        #expect(chord.duration == Fraction(numerator: 2, denominator: 1))
        // Nor does it leak onto the next note.
        #expect(measure.noteEvents.first?.decorations.isEmpty == true)
        #expect(result.score.warningDiagnostics.map(\.code) == [.constructOutOfOrder])
    }
}
