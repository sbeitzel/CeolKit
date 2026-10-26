// User-defined symbols, U: (ABC v2.2 §4.16; issue #254).
//
// Expected decorations are abcm2ps's (8.14, `-g`): a U: definition replaces a symbol's
// default meaning; one in the file header holds for every tune, one in a tune header ends
// with that tune, and an inline [U:] holds from where it is written.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("User-defined symbols (#254)")
struct UserSymbolTests {

    private func decorations(_ tune: Tune?) -> [[Decoration]] {
        (tune?.singleVoiceMeasures.first?.noteEvents ?? []).map(\.decorations)
    }

    @Test("U: defines a letter that has no default meaning")
    func definesNewSymbol() {
        let result = parse("X:1\nL:1/4\nU:W=!fermata!\nK:C\nWC D E F|")
        let decs = decorations(result.score.firstTune)
        #expect(decs == [[.fermata], [], [], []])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("U: redefines a symbol with a default meaning")
    func redefinesPredefinedSymbol() {
        let decs = decorations(parse("X:1\nL:1/4\nU:T=!fermata!\nK:C\nTC D E F|").score.firstTune)
        #expect(decs == [[.fermata], [], [], []])
    }

    @Test("U: defines a lowercase letter")
    func definesLowercaseSymbol() {
        let decs = decorations(parse("X:1\nL:1/4\nU:h=!upbow!\nK:C\nhC D E F|").score.firstTune)
        #expect(decs == [[.upbow], [], [], []])
    }

    @Test("A file-header U: holds for every tune; a tune's own U: ends with the tune")
    func scope() {
        let abc = """
            U:W=!fermata!

            X:1
            L:1/4
            U:T=!fermata!
            K:C
            WC TD [U:W=!trill!]WE F|

            X:2
            L:1/4
            K:C
            WC TD E F|
            """
        let tunes = parse(abc).score.tunes
        #expect(tunes.count == 2)
        #expect(decorations(tunes.first) == [[.fermata], [.fermata], [.trill], []])
        #expect(decorations(tunes.last) == [[.fermata], [.trill], [], []])
    }

    @Test("J and R have abcm2ps's default meanings")
    func abcm2psDefaults() {
        let decs = decorations(parse("X:1\nL:1/4\nK:C\nJC RD E F|").score.firstTune)
        #expect(decs == [[.unknown("slide")], [.roll], [], []])
    }

    @Test("An undefined symbol is reported once and ignored")
    func undefinedSymbol() {
        let result = parse("X:1\nL:1/4\nK:C\nWC D E F|")
        let decs = decorations(result.score.firstTune)
        #expect(decs == [[], [], [], []])
        let diagnostics = result.diagnostics
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.code == .reservedCharacter)
    }
}
