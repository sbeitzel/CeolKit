import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #187: `W:` words (ABC v2.2 §5) were parsed and then dropped by the semantic pass,
/// so the verses printed below a tune never reached the model.
@Suite("W: words reach the tune")
struct WordsFieldTests {

    private func words(_ abc: String) -> [String] {
        CeolKitParser().parse(abc, options: .default).score.tunes[0].words.map(\.value)
    }

    @Test("W: after the music is kept, in source order")
    func bodyWordsAreKept() {
        #expect(words("X:1\nT:t\nK:C\n\"Am\"C|]\nW:hello there\nW:second line\n")
                == ["hello there", "second line"])
    }

    @Test("W: in the header comes before W: in the body")
    func headerThenBody() {
        #expect(words("X:1\nT:t\nW:from the header\nK:C\nC|]\nW:from the body\n")
                == ["from the header", "from the body"])
    }

    @Test("An empty W: is kept as an empty line")
    func emptyLineIsKept() {
        #expect(words("X:1\nT:t\nK:C\nC|]\nW:\nW:verse\nW:\n") == ["", "verse", ""])
    }

    @Test("Indentation and inner spacing are kept; the space after the colon is not")
    func spacingIsKept() {
        let abc = "X:1\nT:t\nK:C\nC|]\nW:C'est Monsieur d'la Miranda        |\n"
            + "W:      Parlé :\nW: one space after the colon\n"
        #expect(words(abc) == ["C'est Monsieur d'la Miranda        |",
                               "     Parlé :",
                               "one space after the colon"])
    }

    @Test("A tune with no W: has no words")
    func noWords() {
        #expect(words("X:1\nT:t\nK:C\nC|]\n").isEmpty)
    }
}
