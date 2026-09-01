import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #126: the clef a `K:` line states never reached the page — the renderer takes the
/// clef from `VoiceProperties`, and only a `V:` field ever wrote one there, so the tune in
/// the issue was drawn on a treble staff.
///
/// The two spellings are the same instruction, so the page they produce is the same page.
/// Comparing the whole document is the point: it says the clef reaches everything drawn
/// from it — the glyph, the key signature's positions, the notes' — and not just the glyph.
@Suite("K: clef= on the page")
struct KeyClefRenderTests {

    private func render(_ body: String) throws -> String {
        let score = CeolKitParser().parse("""
            X:1
            T:Clef
            M:4/4
            L:1/4
            \(body)
            """, options: .default).score
        let svgs = try textProbeRenderer().render(score)
        // The source line an anchor names differs between two spellings of the same tune;
        // nothing drawn does.
        return try #require(svgs.first)
            .components(separatedBy: "\n")
            .filter { !$0.contains("ceolkit-meta") }
            .joined(separator: "\n")
    }

    @Test("A clef on the tune's K: draws what the same clef on V: draws")
    func keyClefMatchesVoiceClef() throws {
        #expect(try render("K:E clef=bass\nCDEC |")
                == (try render("K:E\nV:1 clef=bass\nCDEC |")))
    }

    @Test("...and is not what a tune stating no clef draws")
    func keyClefIsNotTreble() throws {
        #expect(try render("K:E clef=bass\nCDEC |") != (try render("K:E\nCDEC |")))
    }

    @Test("A clef on a voice's own K: draws the voice's clef")
    func voiceKeyClefMatchesVoiceClef() throws {
        #expect(try render("K:E\nV:1\nK:E clef=alto\nCDEC |")
                == (try render("K:E\nV:1 clef=alto\nCDEC |")))
    }
}
