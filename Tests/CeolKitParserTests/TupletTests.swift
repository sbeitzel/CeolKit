// Issues #231 and #232: what the semantic pass makes of a tuplet's notes — how they beam,
// how long they last, and the `q` a tuplet gets when it is not written.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Tuplets")
struct TupletTests {

    private func tune(_ body: String, meter: String = "4/4") -> String {
        "X:1\nT:Test\nM:\(meter)\nL:1/8\nK:C\n\(body)\n"
    }

    private func firstMeasure(_ body: String, meter: String = "4/4") -> Measure? {
        parse(tune(body, meter: meter)).score.firstTune?.singleVoiceMeasures.first
    }

    private func firstTuplet(_ body: String, meter: String = "4/4") -> Tuplet? {
        firstMeasure(body, meter: meter)?.tupletEvents.first
    }

    private func beams(_ events: [Event]) -> [BeamState] {
        events.compactMap {
            switch $0 {
            case .note(let n):  return n.beam
            case .chord(let c): return c.beam
            default:            return nil
            }
        }
    }

    // MARK: - #231: beaming

    @Test("A triplet of eighths is one beam group")
    func tripletBeams() throws {
        let tuplet = try #require(firstTuplet("(3abc z2 z4 |"))
        #expect(beams(tuplet.events) == [.start, .middle, .end])
    }

    @Test("A space after the tuplet specifier is ignored", arguments: ["(3 abc z2 z4 |", "(3abc z2 z4 |"])
    func leadingSpaceIgnored(_ body: String) throws {
        let tuplet = try #require(firstTuplet(body))
        #expect(tuplet.events.count == 3)
        #expect(beams(tuplet.events) == [.start, .middle, .end])
    }

    @Test("A tuplet beams with the notes either side of it, as if the (3 were not there")
    func beamsThroughTuplet() throws {
        let measure = try #require(firstMeasure("ab(3cde fg z2 |"))
        var flat: [Event] = []
        for event in measure.events {
            if case .tuplet(let t) = event { flat += t.events } else { flat.append(event) }
        }
        #expect(beams(flat) == [.start, .middle, .middle, .middle, .end, .start, .end])
    }

    @Test("A triplet of quarters is not beamed, though each sounds shorter than a quarter")
    func quarterTripletUnbeamed() throws {
        let tuplet = try #require(firstTuplet("(3c2d2e2 z2 |"))
        #expect(beams(tuplet.events) == [.single, .single, .single])
    }

    // MARK: - #231: durations

    @Test("A rest in a tuplet is scaled by q/p like its notes")
    func restIsScaled() throws {
        let tuplet = try #require(firstTuplet("(3zab z2 z4 |"))
        guard case .rest(let rest) = tuplet.events.first else {
            Issue.record("Expected the tuplet to open with its rest")
            return
        }
        #expect(rest.duration == Fraction(numerator: 2, denominator: 3))
    }

    // MARK: - #232: the default q

    @Test("An unwritten q follows the §4.13 table", arguments: [
        ("(2ab",       "4/4", 2, 3),
        ("(3abc",      "4/4", 3, 2),
        ("(4abcd",     "4/4", 4, 3),
        ("(5abcde",    "4/4", 5, 2),
        ("(6abcdef",   "4/4", 6, 2),
        ("(7abcdefg",  "4/4", 7, 2),
        ("(8abcdefga", "4/4", 8, 3),
        ("(2ab",       "6/8", 2, 3),
        ("(3abc",      "6/8", 3, 2),
        ("(5abcde",    "6/8", 5, 3),
        ("(6abcdef",   "6/8", 6, 2),
        ("(9abcdefga", "9/8", 9, 3),
    ])
    func defaultQ(_ body: String, _ meter: String, _ p: Int, _ q: Int) throws {
        let tuplet = try #require(firstTuplet(body + " |", meter: meter))
        #expect(tuplet.p == p)
        #expect(tuplet.q == q)
    }

    @Test("A written q is kept")
    func writtenQ() throws {
        let tuplet = try #require(firstTuplet("(3:4abc |"))
        #expect(tuplet.q == 4)
    }
}
