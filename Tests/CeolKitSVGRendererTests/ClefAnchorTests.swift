import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #127: `clef=bass3` (baritone) is the F clef on the *third* line, but was drawn at
/// the same y as `clef=bass`, on the fourth. Every pitch on the staff was then read a third
/// off, and the baritone key-signature table from #98 disagreed with the clef above it.
///
/// The whole switch is covered rather than the one entry that was wrong: the clef's anchor
/// is what fixes the meaning of everything else on the staff, so each one is worth stating.
@Suite("Where a clef anchors on the staff")
struct ClefAnchorTests {

    /// The staff position the clef glyph of `abcClef` is drawn at: 0 = bottom line, 8 = top,
    /// one per diatonic step. An F clef anchors on the line it names F3 on, a G clef on the
    /// line it names G4 on, a C clef on middle C's line.
    private func anchor(of abcClef: String) throws -> Int {
        let score = CeolKitParser().parse("""
            X:1
            T:Clef
            M:4/4
            L:1/4
            K:C
            V:1 clef=\(abcClef)
            CDEC |
            """, options: .default).score
        let svgs   = try textProbeRenderer().render(score)
        let svg    = try #require(svgs.first)
        let page   = try #require(try SVGGeometry.pages(from: svgs).first)
        let system = try #require(page.systems.first)

        let clef      = try #require(clefGlyph(for: ClefSpec(clef: parsedClef(abcClef), octaveShift: 0)))
        let character = String(clef.character)
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard segment.contains(character) else { continue }
            guard let start = segment.range(of: "y=\""),
                  let end = segment[start.upperBound...].firstIndex(of: "\""),
                  let y = Double(segment[start.upperBound..<end]) else { continue }
            return Int(((system.bottomY - y) / (system.staffLineGap / 2)).rounded())
        }
        Issue.record("no \(clef.rawValue) drawn for clef=\(abcClef)")
        return -1
    }

    /// The clef the renderer will be handed, so the probe looks for the glyph actually drawn.
    private func parsedClef(_ abcClef: String) -> Clef {
        let score = CeolKitParser().parse("""
            X:1
            T:Clef
            M:4/4
            L:1/4
            K:C
            V:1 clef=\(abcClef)
            C |
            """, options: .default).score
        return score.tunes.first?.voices.first?.properties.clef.clef ?? .none
    }

    // MARK: - The bug as filed

    @Test("bass3 anchors its F clef on the third line, bass on the fourth")
    func baritoneIsALineAboveBass() throws {
        #expect(try anchor(of: "bass3") == 4)
        #expect(try anchor(of: "bass")  == 6)
    }

    /// Two staff positions per line, counting from the bottom: line 1 is 0, line 5 is 8.
    @Test("Every clef anchors on the line it names",
          arguments: [("treble", 2),        // G4 on line 2
                      ("bass", 6),          // F3 on line 4
                      ("bass3", 4),         // F3 on line 3
                      ("baritone", 4),
                      ("soprano", 0),       // C4 on line 1
                      ("mezzosoprano", 2),  // C4 on line 2
                      ("alto", 4),          // C4 on line 3
                      ("tenor", 6),         // C4 on line 4
                      ("perc", 4)])         // centred; names no pitch
    func clefAnchors(abcClef: String, position: Int) throws {
        #expect(try anchor(of: abcClef) == position)
    }
}
