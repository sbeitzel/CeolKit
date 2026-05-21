// Decoration conformance tests. ABC §4.14.
// Tests both long-form !…! decorations and short-form single-character decorations.
import Testing
import CeolKitModel
import CeolKitParser

private func decTune(_ noteWithDec: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(noteWithDec)|"
}

@Suite("Decorations")
struct DecorationTests {

    // MARK: Long-form dynamics

    @Test("!ppp! applies ppp decoration")
    func ppp() {
        let result = parse(decTune("!ppp!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.ppp) == true)
    }

    @Test("!pp! applies pp decoration")
    func pp() {
        let result = parse(decTune("!pp!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.pp) == true)
    }

    @Test("!p! applies p decoration")
    func p() {
        let result = parse(decTune("!p!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.p) == true)
    }

    @Test("!mp! applies mp decoration")
    func mp() {
        let result = parse(decTune("!mp!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.mp) == true)
    }

    @Test("!mf! applies mf decoration")
    func mf() {
        let result = parse(decTune("!mf!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.mf) == true)
    }

    @Test("!f! applies f decoration")
    func f() {
        let result = parse(decTune("!f!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.f) == true)
    }

    @Test("!ff! applies ff decoration")
    func ff() {
        let result = parse(decTune("!ff!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.ff) == true)
    }

    @Test("!fff! applies fff decoration")
    func fff() {
        let result = parse(decTune("!fff!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fff) == true)
    }

    @Test("!sfz! applies sfz decoration")
    func sfz() {
        let result = parse(decTune("!sfz!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.sfz) == true)
    }

    // MARK: Long-form articulations

    @Test("!staccato! applies staccato decoration")
    func staccato() {
        let result = parse(decTune("!staccato!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.staccato) == true)
    }

    @Test("!tenuto! applies tenuto decoration")
    func tenuto() {
        let result = parse(decTune("!tenuto!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.tenuto) == true)
    }

    @Test("!accent! applies accent decoration")
    func accent() {
        let result = parse(decTune("!accent!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.accent) == true)
    }

    // MARK: Long-form ornaments

    @Test("!trill! applies trill decoration")
    func trill() {
        let result = parse(decTune("!trill!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.trill) == true)
    }

    @Test("!roll! applies roll decoration")
    func roll() {
        let result = parse(decTune("!roll!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.roll) == true)
    }

    @Test("!fermata! applies fermata decoration")
    func fermata() {
        let result = parse(decTune("!fermata!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fermata) == true)
    }

    @Test("!mordent! applies mordent decoration")
    func mordent() {
        let result = parse(decTune("!mordent!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.mordent) == true)
    }

    @Test("!turn! applies turn decoration")
    func turn() {
        let result = parse(decTune("!turn!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.turn) == true)
    }

    // MARK: Long-form bowing

    @Test("!upbow! applies upbow decoration")
    func upbow() {
        let result = parse(decTune("!upbow!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.upbow) == true)
    }

    @Test("!downbow! applies downbow decoration")
    func downbow() {
        let result = parse(decTune("!downbow!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.downbow) == true)
    }

    // MARK: Hairpins

    @Test("!<(! applies crescendoStart decoration")
    func crescendoStart() {
        let result = parse(decTune("!<(!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.crescendoStart) == true)
    }

    @Test("!<)! applies crescendoEnd decoration")
    func crescendoEnd() {
        let result = parse(decTune("!<)!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.crescendoEnd) == true)
    }

    @Test("!>(! applies decrescendoStart decoration")
    func decrescendoStart() {
        let result = parse(decTune("!>(!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.decrescendoStart) == true)
    }

    // MARK: Navigation

    @Test("!segno! applies segno decoration")
    func segno() {
        let result = parse(decTune("!segno!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.segno) == true)
    }

    @Test("!coda! applies coda decoration")
    func coda() {
        let result = parse(decTune("!coda!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.coda) == true)
    }

    @Test("!fine! applies fine decoration")
    func fine() {
        let result = parse(decTune("!fine!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fine) == true)
    }

    @Test("!D.C.! applies dacapo decoration")
    func dacapo() {
        let result = parse(decTune("!D.C.!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.dacapo) == true)
    }

    // MARK: Short-form decorations (expanded in semantic pass)

    @Test(". (dot) expands to staccato")
    func dotIsStaccato() {
        let result = parse(decTune(".C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.staccato) == true)
    }

    @Test("~ (tilde) expands to roll")
    func tildeIsRoll() {
        let result = parse(decTune("~C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.roll) == true)
    }

    @Test("H expands to fermata")
    func hIsFermata() {
        let result = parse(decTune("HC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fermata) == true)
    }

    @Test("L expands to accent")
    func lIsAccent() {
        let result = parse(decTune("LC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.accent) == true)
    }

    @Test("M expands to mordent")
    func mIsMordent() {
        let result = parse(decTune("MC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.mordent) == true)
    }

    @Test("O expands to coda")
    func oIsCoda() {
        let result = parse(decTune("OC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.coda) == true)
    }

    @Test("P expands to pralltriller")
    func pIsPralltriller() {
        let result = parse(decTune("PC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.pralltriller) == true)
    }

    @Test("S expands to segno")
    func sIsSegno() {
        let result = parse(decTune("SC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.segno) == true)
    }

    @Test("T expands to trill")
    func tIsTrill() {
        let result = parse(decTune("TC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.trill) == true)
    }

    @Test("u expands to upbow")
    func uIsUpbow() {
        let result = parse(decTune("uC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.upbow) == true)
    }

    @Test("v expands to downbow")
    func vIsDownbow() {
        let result = parse(decTune("vC"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.downbow) == true)
    }

    // MARK: Fingering

    @Test("!1! applies fingering(1) decoration")
    func fingering1() {
        let result = parse(decTune("!1!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fingering(1)) == true)
    }

    @Test("!5! applies fingering(5) decoration")
    func fingering5() {
        let result = parse(decTune("!5!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.fingering(5)) == true)
    }

    // MARK: Unknown decorations

    @Test("Unknown !xyzzy! stored as .unknown(\"xyzzy\")")
    func unknownDecoration() {
        let result = parse(decTune("!xyzzy!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        let hasUnknown = note?.decorations.contains(.unknown("xyzzy")) == true
        #expect(hasUnknown)
    }

    // MARK: Multiple decorations on one note

    @Test("!pp!!trill! stacks both decorations on the same note")
    func multipleDecorations() {
        let result = parse(decTune("!pp!!trill!C"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        #expect(note?.decorations.contains(.pp) == true)
        #expect(note?.decorations.contains(.trill) == true)
    }
}
