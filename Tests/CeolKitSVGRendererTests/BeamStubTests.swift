import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #240: a stub beam on a note in the middle of a beam group points toward the
/// neighbour it is paired with in the rhythm.
///
/// The expected directions are abcm2ps's (8.14, `-g`, `draw_beams`): the first note's stub
/// points right and the last note's left; one in the middle points right where the note
/// before it has fewer beams than the note after, or as many and fewer dots.
@Suite("Beam stubs (#240)")
struct BeamStubTests {

    private enum Direction { case left, right }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private var stemThickness: Double { metadata.engravingDefaults.stemThickness * s }
    private var beamThickness: Double { metadata.engravingDefaults.beamThickness * s }

    private func render(_ body: String) throws -> String {
        let abc = "X:1\nT:Stubs\nM:2/4\nL:1/16\nK:D\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        return try textProbeRenderer().render(score).joined()
    }

    private func lines(in svg: String, width: Double) -> [(x1: Double, y1: Double, x2: Double, y2: Double)] {
        svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5), abs(w - width) < 0.01 else { return nil }
            return (x1, y1, x2, y2)
        }
    }

    /// Which way the one stub of the bar's first beam group points, and the index of the
    /// stem it hangs from.
    private func stub(in body: String) throws -> (stem: Int, direction: Direction) {
        let svg = try render(body)
        let stemXs = lines(in: svg, width: stemThickness)
            .filter { $0.x1 == $0.x2 && $0.y1 != $0.y2 }
            .map(\.x1)
            .sorted()
        // A stub is a beam that reaches no second stem.
        let stubs = lines(in: svg, width: beamThickness)
            .filter { $0.y1 == $0.y2 }
            .filter { beam in
                stemXs.filter { $0 >= beam.x1 - stemThickness && $0 <= beam.x2 + stemThickness }
                    .count == 1
            }
        let stub = try #require(stubs.count == 1 ? stubs[0] : nil)
        let stem = try #require(stemXs.firstIndex {
            $0 >= stub.x1 - stemThickness && $0 <= stub.x2 + stemThickness
        })
        let stemX = stemXs[stem]
        return (stem, stub.x2 - stemX > stemX - stub.x1 ? .right : .left)
    }

    @Test("A middle note points its stub at the dotted partner after it")
    func pointsRightTowardBrokenRhythmPartner() throws {
        // B and e have two beams each; B has no dot and e has one.
        let result = try stub(in: "Bc<e z z4 |")
        #expect(result.stem == 1)
        #expect(result.direction == .right)
    }

    @Test("A middle note points its stub at the dotted partner before it")
    func pointsLeftTowardBrokenRhythmPartner() throws {
        // B has the dot, e none.
        let result = try stub(in: "B>ce z z4 |")
        #expect(result.stem == 1)
        #expect(result.direction == .left)
    }

    @Test("A middle note points its stub at the neighbour with more beams")
    func pointsTowardMoreBeams() throws {
        // c is a 64th between a 32nd and a 16th, then between a 16th and a 32nd.
        #expect(try stub(in: "B/c/4d z6 |").direction == .left)
        #expect(try stub(in: "dc/4B/ z6 |").direction == .right)
    }

    @Test("The first note's stub points right and the last note's left")
    func endsPointInward() throws {
        let first = try stub(in: "c<eB2 z4 |")
        #expect(first.stem == 0)
        #expect(first.direction == .right)
        let last = try stub(in: "B2e>c z4 |")
        #expect(last.stem == 2)
        #expect(last.direction == .left)
    }
}
