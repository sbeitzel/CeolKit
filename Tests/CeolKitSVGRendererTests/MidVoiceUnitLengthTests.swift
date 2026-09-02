import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #122: an `L:` that moves part way through a voice has to reach the renderer.
///
/// The parser records the effective unit note length on every `Measure` (#85 and #122), and
/// the sizer and emitter read it from there. Before this, the renderer resolved one unit
/// note length per voice and drew every bar of that voice against it, so a bar after a
/// mid-voice `[L:]` came out at the length the voice *opened* in — flagged sixteenths where
/// the parser had already resolved unbeamable whole notes.
@Suite("Mid-voice [L:] reaches the renderer")
struct MidVoiceUnitLengthTests {

    private func render(_ abc: String) throws -> (svg: String, system: SystemGeometry) {
        let score = CeolKitParser().parse(abc, options: .default).score
        let svgs = try textProbeRenderer().render(score)
        let svg = try #require(svgs.first)
        let page = try #require(try SVGGeometry.pages(from: svgs).first)
        let system = try #require(page.systems.first)
        return (svg, system)
    }

    /// The x positions of every `<text>` run carrying `glyph`.
    private func xs(of glyph: SMuFLGlyph, in svg: String) -> [Double] {
        let character = String(glyph.character)
        return svg.components(separatedBy: "<text ").dropFirst().compactMap { segment in
            guard segment.contains(character),
                  let start = segment.range(of: "x=\""),
                  let end = segment[start.upperBound...].firstIndex(of: "\"")
            else { return nil }
            return Double(segment[start.upperBound..<end])
        }
    }

    /// How many of `positions` fall in each bar of `system`, in bar order.  The bar lines
    /// the geometry reads back are the cuts; anything left of the first is the staff head.
    private func countPerBar(_ positions: [Double], in system: SystemGeometry) -> [Int] {
        let cuts = system.barlineXs.sorted()
        var counts = [Int](repeating: 0, count: cuts.count)
        for x in positions {
            guard let bar = cuts.firstIndex(where: { x < $0 }) else { continue }
            counts[bar] += 1
        }
        return counts
    }

    /// The issue's own reproduction: sixteen sixteenths, then `[L:1/1]`, then two bars that
    /// are sixteen whole notes.
    private let midChange = """
        X:1
        T:Mid change
        M:4/4
        L:1/16
        K:C
        cccc cccc | [L:1/1] cccc cccc | cccc cccc |
        """

    @Test("The bar after a mid-voice [L:] is drawn at the new unit length")
    func changeReachesTheNoteheads() throws {
        let (svg, system) = try render(midChange)

        // Bar 1 is written in sixteenths, bars 2 and 3 in whole notes.
        #expect(countPerBar(xs(of: .noteheadBlack, in: svg), in: system) == [8, 0, 0])
        #expect(countPerBar(xs(of: .noteheadWhole, in: svg), in: system) == [0, 8, 8])
        // A whole note has neither stem nor flag, so every flag on the page is bar 1's —
        // and bar 1's eight sixteenths beam in two groups of four, so it has none either.
        #expect(xs(of: .flag16thDown, in: svg).isEmpty)
        #expect(xs(of: .flag16thUp, in: svg).isEmpty)
    }

    @Test("The change carries forward to later bars until another L: moves it")
    func changeCarriesForwardAndIsMovedAgain() throws {
        let (svg, system) = try render("""
            X:1
            M:4/4
            L:1/16
            K:C
            cccc cccc | [L:1/1] cccc cccc | [L:1/16] cccc cccc |
            """)
        #expect(countPerBar(xs(of: .noteheadBlack, in: svg), in: system) == [8, 0, 8])
        #expect(countPerBar(xs(of: .noteheadWhole, in: svg), in: system) == [0, 8, 0])
    }

    @Test("Whole notes take more room than the sixteenths they replaced")
    func theSystemIsWiderThanTheUnchangedTune() throws {
        let (_, changed) = try render(midChange)
        let (_, unchanged) = try render(midChange.replacing("[L:1/1] ", with: ""))
        #expect(changed.width > unchanged.width)
    }

    @Test("A mid-voice [L:] belongs to the voice that carries it")
    func changeDoesNotLeakToAnotherVoice() throws {
        // Voice 1 changes to whole notes half way through; voice 2 says nothing and stays in
        // sixteenths.  Both staves are read together, so the count is the sum of the two.
        let (svg, system) = try render("""
            X:1
            M:4/4
            L:1/16
            K:C
            V:1
            V:2
            [V:1] cccc cccc | [L:1/1] cccc cccc |
            [V:2] cccc cccc | cccc cccc |
            """)
        #expect(countPerBar(xs(of: .noteheadBlack, in: svg), in: system) == [16, 8])
        #expect(countPerBar(xs(of: .noteheadWhole, in: svg), in: system) == [0, 8])
    }
}
