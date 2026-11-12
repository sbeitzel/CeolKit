// Decorations written before a grace group. ABC §4.12, §4.14.
//
// Issue #267: `T{gef}e` put the trill on the first grace note, where nothing draws it.
// abcm2ps 8.14 trills the `e`, and pipe and Irish music often write the decoration ahead of
// the gracing.  A decoration written inside the braces still belongs to its grace note.
import Testing
import CeolKitModel
import CeolKitParser

private func graceTune(_ body: String) -> String {
    "X:1\nT:Test\nL:1/8\nK:D\n\(body)|]"
}

@Suite("Decorations before a grace group")
struct GraceDecorationTests {

    private func firstMeasure(_ body: String) throws -> Measure {
        let result = parse(graceTune(body))
        return try #require(result.score.firstTune?.singleVoiceMeasures.first)
    }

    @Test("T{gef}e, !trill!{gef}e and {gef}!trill!e all trill the e")
    func trillBeforeOrAfterGraceGoesToMainNote() throws {
        let measure = try firstMeasure("T{gef}e2 !trill!{gef}e2 {gef}!trill!e2 ")
        let graces = measure.graceEvents
        let mains = measure.noteEvents
        #expect(graces.count == 3)
        #expect(mains.count == 3)
        for grace in graces {
            #expect(grace.notes.allSatisfy { $0.decorations.isEmpty })
        }
        for main in mains {
            #expect(main.decorations == [.trill])
        }
    }

    @Test("A decoration inside the braces stays on its grace note")
    func decorationInsideGraceStaysOnGraceNote() throws {
        let measure = try firstMeasure("!trill!{g!accent!ef}e2 ")
        let grace = try #require(measure.graceEvents.first)
        let main = try #require(measure.noteEvents.first)
        #expect(grace.notes.map(\.decorations) == [[], [.accent], []])
        #expect(main.decorations == [.trill])
    }

    @Test("A decoration before the group and one after it both reach the main note")
    func decorationsEitherSideOfGraceCombine() throws {
        let measure = try firstMeasure("!trill!{g}!accent!e2 ")
        let grace = try #require(measure.graceEvents.first)
        let main = try #require(measure.noteEvents.first)
        #expect(grace.notes.allSatisfy { $0.decorations.isEmpty })
        #expect(main.decorations == [.trill, .accent])
    }

    @Test("A decoration before a group left open at the line end is not lost")
    func decorationBeforeUnclosedGraceCarriesOn() throws {
        let result = parse("X:1\nT:Test\nL:1/8\nK:D\nT{gef\ne2|]")
        let measure = try #require(result.score.firstTune?.singleVoiceMeasures.first)
        let main = try #require(measure.noteEvents.first)
        #expect(main.decorations == [.trill])
    }
}
