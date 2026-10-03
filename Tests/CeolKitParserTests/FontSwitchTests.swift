import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #204: the in-string font switches `$0` … `$4` of ABC v2.2 §11.4.2.
@Suite("In-string font switches (§11.4.2)")
struct FontSwitchTests {

    private typealias Run = FontSwitch.Run

    // MARK: - Splitting

    @Test("A switch sets the rest of the string, up to the next one")
    func runs() {
        let split = FontSwitch.runs(in: "Reel $1in D$0, traditional")
        #expect(split.runs == [Run(font: 0, text: "Reel "), Run(font: 1, text: "in D"),
                               Run(font: 0, text: ", traditional")])
        #expect(split.endFont == 0)
    }

    @Test("$$ is a dollar sign, and is never read as a switch")
    func dollar() {
        #expect(FontSwitch.runs(in: "$$5 and $$1").runs == [Run(font: 0, text: "$5 and $1")])
        #expect(FontSwitch.plainText("costs $$5") == "costs $5")
        #expect(FontSwitch.fonts(switchedTo: "$$1") == [])
    }

    @Test("Only $0 to $4 switch; any other $ is printed", arguments: ["$5", "$x", "end $", "$9z"])
    func notSwitches(_ text: String) {
        #expect(FontSwitch.runs(in: text).runs == [Run(font: 0, text: text)])
        #expect(FontSwitch.plainText(text) == text)
    }

    @Test("A string can start in a carried font, and reports the font it ends in")
    func carried() {
        let split = FontSwitch.runs(in: "b", startingWith: 2)
        #expect(split.runs == [Run(font: 2, text: "b")])
        #expect(split.endFont == 2)
        // A switch alone draws nothing, but changes the font.
        #expect(FontSwitch.runs(in: "$3").runs.isEmpty)
        #expect(FontSwitch.runs(in: "$3").endFont == 3)
    }

    @Test("The plain text and the switches made")
    func plainAndFonts() {
        #expect(FontSwitch.plainText("$1Fine$0 ok") == "Fine ok")
        #expect(FontSwitch.plainText("no switch") == "no switch")
        #expect(FontSwitch.fonts(switchedTo: "$1a$0b$4c$2") == [1, 4, 2])
    }

    // MARK: - Chord symbols

    private func chordSymbol(_ quoted: String) -> (ChordSymbol?, [Diagnostic]) {
        let score = CeolKitParser().parse("X:1\nT:t\nK:C\n\"\(quoted)\"C|]\n", options: .default).score
        guard case .note(let note)? = score.tunes.first?.voices.first?.staves.first?
            .measures.first?.events.first else { return (nil, score.diagnostics) }
        return (note.chordSymbol, score.diagnostics)
    }

    @Test("A chord symbol is read through its switches, which stay in its text")
    func chordSymbolSwitch() {
        let (symbol, diagnostics) = chordSymbol("G$1m")
        #expect(symbol?.root == PitchClass(step: .g, alteration: .natural))
        #expect(symbol?.quality == "m")
        #expect(symbol?.raw == "G$1m")
        #expect(symbol?.segments == [.text("G$1m")])
        #expect(!diagnostics.contains { $0.code == .unrecognisedChordSymbol })
    }

    @Test("A switch around a chord symbol's accidental stays in the text beside it")
    func chordSymbolAccidental() {
        let (symbol, _) = chordSymbol("$1Bb7$0")
        #expect(symbol?.root == PitchClass(step: .b, alteration: .flat))
        #expect(symbol?.quality == "7")
        #expect(symbol?.segments == [.text("$1B"), .accidental(.flat), .text("7$0")])

        let (before, _) = chordSymbol("B$2b7")
        #expect(before?.root == PitchClass(step: .b, alteration: .flat))
        #expect(before?.segments == [.text("B$2"), .accidental(.flat), .text("7")])
    }

    // MARK: - Lyrics

    private func syllables(_ abc: String, verse: Int = 0) -> [String] {
        let score = CeolKitParser().parse(abc, options: .default).score
        let events = score.tunes.first?.voices.first?.staves.first?.measures
            .flatMap(\.events) ?? []
        return events.compactMap { event in
            guard case .note(let note) = event, verse < note.lyrics.count,
                  case .text(let text, _)? = note.lyrics[verse] else { return nil }
            return text.value
        }
    }

    @Test("A switch in a w: line holds for the syllables after it, to a $0")
    func lyricsCarry() {
        let abc = "X:1\nT:t\nK:C\nCDEF|GABc|]\nw:a $1b c d $0e f $2g h\n"
        #expect(syllables(abc) == ["a", "$1b", "$1c", "$1d", "$0e", "f", "$2g", "$2h"])
    }

    @Test("A switch does not carry from one verse to the next")
    func lyricsPerLine() {
        let abc = "X:1\nT:t\nK:C\nCD|]\nw:$1a b\nw:c d\n"
        #expect(syllables(abc, verse: 0) == ["$1a", "$1b"])
        #expect(syllables(abc, verse: 1) == ["c", "d"])
    }
}
