import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #233: a chord has one stem, with one flag, or a share of a beam.
///
/// Each note of a chord used to draw a stem and flag of its own, so an eighth-note chord of
/// two notes read as a sixteenth, and chords were never beamed: beaming only looked at notes.
///
/// The expected directions are abcm2ps's (8.14, `-g`): the outer notes decide, as they do
/// for a beam group, and where they balance an unbeamed chord is decided by all its notes.
@Suite("Chord stems (#233)")
struct ChordStemTests {

    private struct Stem { let x, top, bottom: Double }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize
    /// SVG coordinates are written to three decimals.
    private let tolerance = 0.002

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private var stemThickness: Double { metadata.engravingDefaults.stemThickness * s }
    private var beamThickness: Double { metadata.engravingDefaults.beamThickness * s }

    private func render(_ body: String, meter: String = "2/4") throws -> String {
        let abc = "X:1\nT:Chords\nM:\(meter)\nL:1/8\nK:C\n\(body)\n"
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

    private func stems(in svg: String) -> [Stem] {
        lines(in: svg, width: stemThickness)
            .filter { $0.x1 == $0.x2 && $0.y1 != $0.y2 }
            .map { Stem(x: $0.x1, top: min($0.y1, $0.y2), bottom: max($0.y1, $0.y2)) }
            .sorted { $0.x < $1.x }
    }

    /// The y of every black notehead, grouped by x, left to right.
    private func headColumns(in svg: String) -> [[Double]] {
        let heads = svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/)
            .compactMap { m -> (x: Double, y: Double)? in
                guard let x = Double(m.1), let y = Double(m.2),
                      String(m.3).first == SMuFLGlyph.noteheadBlack.character else { return nil }
                return (x, y)
            }
        return Dictionary(grouping: heads, by: \.x)
            .sorted { $0.key < $1.key }
            .map { $0.value.map(\.y) }
    }

    private func count(_ glyph: SMuFLGlyph, in svg: String) -> Int {
        svg.filter { $0 == glyph.character }.count
    }

    @Test("An unbeamed chord draws one stem and one flag")
    func unbeamedChordHasOneStem() throws {
        // The issue's bar.
        let svg = try render("[ce] [df] [eg] a4 z |", meter: "4/4")
        let stems = stems(in: svg)
        #expect(stems.count == 4)  // three chords and the a
        #expect(count(.flag8thDown, in: svg) + count(.flag8thUp, in: svg) == 3)
        #expect(count(.flag16thDown, in: svg) + count(.flag16thUp, in: svg) == 0)
    }

    @Test("A chord's stem leaves its farthest notehead and runs full length past the nearest")
    func stemSpansTheChord() throws {
        let svg = try render("[ce] [B,G] z2 |")
        let stems = stems(in: svg)
        let columns = headColumns(in: svg)
        try #require(stems.count == 2 && columns.count == 2)

        // [ce] stems down: from the e, past the c.
        let down = stems[0], downHeads = columns[0]
        // It joins the notehead at the SMuFL anchor, within half a space of its centre.
        #expect(abs(down.top - downHeads.min()!) < s / 2)
        #expect(abs(down.bottom - (downHeads.max()! + 3.5 * s)) < tolerance)

        // [B,G] stems up: from the B, past the G.
        let up = stems[1], upHeads = columns[1]
        #expect(abs(up.bottom - upHeads.max()!) < s / 2)
        #expect(abs(up.top - (upHeads.min()! - 3.5 * s)) < tolerance)
    }

    @Test("Chords written together are beamed together")
    func chordsAreBeamed() throws {
        let svg = try render("[ce][df][eg] z |")
        let stems = stems(in: svg)
        #expect(stems.count == 3)
        #expect(count(.flag8thDown, in: svg) + count(.flag8thUp, in: svg) == 0)
        let beams = lines(in: svg, width: beamThickness).filter { $0.y1 == $0.y2 }
        try #require(beams.count == 1)
        // Every stem ends at the beam.
        #expect(stems.allSatisfy { abs($0.bottom - beams[0].y1) < tolerance })
    }

    @Test("A beam group of chords and notes takes one direction from its outermost notes")
    func mixedGroupDirection() throws {
        // c to a: the a is farther above the middle line than the c is.
        let svg = try render("[ce]/[df]/[eg]/a/ z2 |")
        let stems = stems(in: svg)
        let columns = headColumns(in: svg)
        try #require(stems.count == 4 && columns.count == 4)
        for (stem, heads) in zip(stems, columns) {
            #expect(stem.bottom > heads.max()!)  // down
        }
        #expect(lines(in: svg, width: beamThickness).filter { $0.y1 == $0.y2 }.count == 2)
    }

    @Test("Chord stem directions match abcm2ps")
    func directionsMatchAbcm2ps() throws {
        // [DGg] and [Ddg] balance on their outer notes; all three notes decide.
        let svg = try render("[DGg]2 [Ddg]2 | [B,G]2 [Ace]2 |")
        let stems = stems(in: svg)
        let columns = headColumns(in: svg)
        try #require(stems.count == 4 && columns.count == 4)
        let isUp = zip(stems, columns).map { stem, heads in stem.top < heads.min()! - s }
        #expect(isUp == [true, false, true, false])
    }
}
