import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #66: the key signature and unit note length handed to a staff are the voice's own
/// where it states them, not the tune's for everybody.
///
/// End to end, because the bug was in the wiring: both values existed on the layout types
/// already and the driver simply fed `tune.key` and `tune.unitNoteLength` into every one.
@Suite("Per-voice key signature and unit note length")
struct PerVoiceKeyAndLengthTests {

    /// The `<text>` runs carrying `glyph`, as (x, y) pairs.  `.fontFace` output states a
    /// glyph's position directly; outline output would state the same thing through a
    /// transform — see ``textProbeRenderer``.
    private func glyphPositions(of glyph: SMuFLGlyph, in svg: String) -> [(x: Double, y: Double)] {
        let character = String(glyph.character)
        var found: [(x: Double, y: Double)] = []
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard segment.contains(character) else { continue }
            func attribute(_ name: String) -> Double? {
                guard let start = segment.range(of: "\(name)=\"") else { return nil }
                let after = segment[start.upperBound...]
                guard let end = after.firstIndex(of: "\"") else { return nil }
                return Double(after[after.startIndex..<end])
            }
            guard let x = attribute("x"), let y = attribute("y") else { continue }
            found.append((x, y))
        }
        return found
    }

    /// How many of `positions` sit on each staff of `page`, in staff order.  A glyph is
    /// assigned to the staff whose vertical middle it is nearest — the staves of a system are
    /// further apart than a staff is tall, so nothing lands ambiguously.
    private func countPerStaff(_ positions: [(x: Double, y: Double)],
                               on page: PageGeometry) -> [Int] {
        var counts = [Int](repeating: 0, count: page.systems.count)
        for position in positions {
            let nearest = page.systems.indices.min {
                let middleA = page.systems[$0].topY + page.systems[$0].staffLineGap * 2
                let middleB = page.systems[$1].topY + page.systems[$1].staffLineGap * 2
                return abs(position.y - middleA) < abs(position.y - middleB)
            }
            if let nearest { counts[nearest] += 1 }
        }
        return counts
    }

    private func render(_ abc: String) throws -> (svg: String, page: PageGeometry) {
        let score = CeolKitParser().parse(abc, options: .default).score
        let svgs = try textProbeRenderer().render(score)
        let svg = try #require(svgs.first)
        let page = try #require(try SVGGeometry.pages(from: svgs).first)
        return (svg, page)
    }

    // MARK: Key signature

    @Test("A voice with its own K: gets that key signature at the head of its staff")
    func voiceKeySignatureIsDrawnOnItsOwnStaff() throws {
        // The tune is in C and voice 1 is in G. Nothing in the music prints an accidental of
        // its own, so every sharp glyph on the page belongs to a key signature.
        let (svg, page) = try render("""
            X:1
            T:Per-voice key
            M:4/4
            L:1/4
            K:C
            V:1
            K:G
            cdec | cdec |
            V:2
            cdec | cdec |
            """)
        #expect(page.systems.count == 2)   // one system, two staves
        let sharps = countPerStaff(glyphPositions(of: .accidentalSharp, in: svg), on: page)
        #expect(sharps == [1, 0])
    }

    @Test("A voice with no K: of its own keeps the tune's")
    func voiceWithoutItsOwnKeyKeepsTheTunes() throws {
        // The mirror image: the tune's two sharps stand on voice 1's staff, and voice 2's
        // K:C cancels them on its own staff only.
        let (svg, page) = try render("""
            X:1
            T:Per-voice key
            M:4/4
            L:1/4
            K:D
            V:1
            cdec | cdec |
            V:2
            K:C
            cdec | cdec |
            """)
        #expect(page.systems.count == 2)
        let sharps = countPerStaff(glyphPositions(of: .accidentalSharp, in: svg), on: page)
        #expect(sharps == [2, 0])
    }

    @Test("A single-voice tune draws the tune's key, once")
    func singleVoiceIsUnchanged() throws {
        let (svg, page) = try render("""
            X:1
            T:Single
            M:4/4
            L:1/4
            K:D
            cdec | cdec |
            """)
        #expect(page.systems.count == 1)
        #expect(glyphPositions(of: .accidentalSharp, in: svg).count == 2)
    }

    // MARK: Unit note length

    @Test("A voice with its own L: is sized against it")
    func voiceUnitNoteLengthReachesTheSizer() throws {
        // Same music either way — only voice 1's L: differs. Sized against 1/1 its notes are
        // whole notes and need far more room than the 1/16ths the tune's L: would make of
        // them, so the same source line no longer fits in as few systems.
        func systemCount(voiceOneLength: String?) throws -> Int {
            let voiceOneHeader = voiceOneLength.map { "L:\($0)\n" } ?? ""
            let bar = "cccc cccc cccc cccc |"
            return try render("""
                X:1
                T:Per-voice length
                M:4/4
                L:1/16
                K:C
                V:1
                \(voiceOneHeader)\(String(repeating: bar, count: 4))
                V:2
                \(String(repeating: bar, count: 4))
                """).page.systems.count
        }
        let inherited = try systemCount(voiceOneLength: nil)
        let widened = try systemCount(voiceOneLength: "1/1")
        #expect(widened > inherited)
        // And the voice that states nothing is unaffected: with both voices on the tune's L:
        // the count is the same whichever voice we leave alone.
        #expect(inherited == (try systemCount(voiceOneLength: "1/16")))
    }
}
