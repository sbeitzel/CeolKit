import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #243: `!beambr1!` and `!beambr2!` break a beam group's secondary beams before the
/// note they are written on, while the first one or two beams run through.
///
/// The expected beams are abcm2ps's (8.14, `-g`, `draw_beams`): a run of beam level `i`
/// stops before a note carrying `!beambr1!`, or `!beambr2!` where `i > 2`; and a stub on the
/// note a break comes before points right, one on the note before a break left.
@Suite("Beam breaks (#243)")
struct BeamBreakRenderTests {

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private var stemThickness: Double { metadata.engravingDefaults.stemThickness * s }
    private var beamThickness: Double { metadata.engravingDefaults.beamThickness * s }

    private typealias Line = (x1: Double, y1: Double, x2: Double, y2: Double)

    private func lines(in svg: String, width: Double) -> [Line] {
        svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5), abs(w - width) < 0.01 else { return nil }
            return (x1, y1, x2, y2)
        }
    }

    /// The beams of the bar's first beam group, level by level from the primary beam out,
    /// each as the indices of the stems it reaches.  A stub reaches one stem, and is given
    /// with the side it points to: `[2, 3]` is a run, `[1, -1]` a stub on stem 1 pointing
    /// left, `[1, +1]` one pointing right.
    private func beams(in body: String) throws -> [[[Int]]] {
        let abc = "X:1\nT:Breaks\nM:2/4\nL:1/16\nK:D\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        let svg = try textProbeRenderer().render(score).joined()
        let stemXs = lines(in: svg, width: stemThickness)
            .filter { $0.x1 == $0.x2 && $0.y1 != $0.y2 }
            .map(\.x1)
            .sorted()
        let beams = lines(in: svg, width: beamThickness).filter { $0.y1 == $0.y2 }
        // The first group's beams are the ones that reach its first stem's level.
        let primary = try #require(beams.min { $0.x1 < $1.x1 })
        let group = beams.filter { $0.x2 <= primary.x2 + stemThickness }
        let byLevel = Dictionary(grouping: group, by: \.y1)
            .sorted { abs($0.key - primary.y1) < abs($1.key - primary.y1) }
        return byLevel.map { _, level in
            level.sorted { $0.x1 < $1.x1 }.map { beam in
                let reached = stemXs.indices.filter {
                    stemXs[$0] >= beam.x1 - stemThickness && stemXs[$0] <= beam.x2 + stemThickness
                }
                guard reached.count == 1, let stem = reached.first else { return reached }
                let x = stemXs[stem]
                return [stem, beam.x2 - x > x - beam.x1 ? 1 : -1]
            }
        }
    }

    @Test("!beambr1! breaks the second beam and keeps the first")
    func beambr1() throws {
        let levels = try beams(in: "Bc!beambr1!de f2g2|")
        #expect(levels == [[[0, 1, 2, 3]], [[0, 1], [2, 3]]])
    }

    @Test("!beambr2! keeps the first two beams and breaks the third")
    func beambr2() throws {
        let levels = try beams(in: "[L:1/32]BcBc!beambr2!dede f4g4|")
        #expect(levels == [
            [[0, 1, 2, 3, 4, 5, 6, 7]],
            [[0, 1, 2, 3, 4, 5, 6, 7]],
            [[0, 1, 2, 3], [4, 5, 6, 7]],
        ])
    }

    @Test("A stub either side of a break points away from it")
    func stubsBesideBreak() throws {
        // Without the break, c would point right at d and d left at c (#240).
        let levels = try beams(in: "B2c!beambr1!de2 f2g2|")
        #expect(levels == [[[0, 1, 2, 3]], [[1, -1], [2, 1]]])
    }

    @Test("A stub on the last note after a break points left")
    func stubAtEndAfterBreak() throws {
        let levels = try beams(in: "Bcd!beambr1!e f2g2|")
        #expect(levels == [[[0, 1, 2, 3]], [[0, 1, 2], [3, -1]]])
    }
}
