import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #223: a `K:` part way through a voice that changes the clef — `K:bass`,
/// `[K:clef=bass]`, `K:G alto` — used to leave every staff in the clef its voice opened in.
///
/// What is drawn is checked against `abcm2ps -g` (8.14):
/// - a change written against a bar line is drawn small, *before* that bar line;
/// - where the bar line ends a system, that small clef is the courtesy clef at the end of
///   the line, and the next system opens with the new clef full size;
/// - a change part way through a bar is drawn small between the notes it falls between;
/// - a change of clef alone draws no key signature where it happens, and the next system's
///   head draws the signature the key already had, for the new clef.
///
/// Read out of the emitted document rather than the layout: what was wrong was the ink.
@Suite("A clef change part way through a voice")
struct MidTuneClefChangeTests {

    private struct Glyph {
        let x: Double
        let y: Double
        let size: Double
        let character: Character
    }

    private struct Page {
        let glyphs: [Glyph]
        let systems: [SystemGeometry]

        /// The system whose staff `glyph` stands on or nearest to.
        func system(of glyph: Glyph) -> Int {
            systems.indices.min {
                abs((systems[$0].topY + systems[$0].bottomY) / 2 - glyph.y)
                    < abs((systems[$1].topY + systems[$1].bottomY) / 2 - glyph.y)
            } ?? 0
        }

        func glyphs(_ characters: Set<Character>, inSystem index: Int) -> [Glyph] {
            glyphs.filter { characters.contains($0.character) && system(of: $0) == index }
                .sorted { $0.x < $1.x }
        }

        func headsX(inSystem index: Int) -> [Double] {
            glyphs(MidTuneClefChangeTests.heads, inSystem: index).map(\.x)
        }

        /// Staff positions of the noteheads on system `index`, left to right: 0 = bottom line.
        func headPositions(inSystem index: Int) -> [Int] {
            let system = systems[index]
            return glyphs(MidTuneClefChangeTests.heads, inSystem: index).map {
                Int(((system.bottomY - $0.y) / (system.staffLineGap / 2)).rounded())
            }
        }
    }

    private static let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                                SMuFLGlyph.noteheadHalf.character,
                                                SMuFLGlyph.noteheadWhole.character]
    private static let gClef = SMuFLGlyph.gClef.character
    private static let fClef = SMuFLGlyph.fClef.character
    private static let cClef = SMuFLGlyph.cClef.character
    private static let clefs: Set<Character> = [gClef, fClef, cClef]
    private static let sharp = SMuFLGlyph.accidentalSharp.character

    private func render(_ body: String) throws -> Page {
        let score = CeolKitParser().parse("""
            X:1
            T:Clef change
            M:4/4
            L:1/4
            \(body)
            """, options: .default).score
        let svgs = try textProbeRenderer().render(score)
        let svg  = try #require(svgs.first)
        let geometry = try #require(try SVGGeometry.pages(from: svgs).first)
        let glyphs = svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura" font-size="([0-9.]+)"[^>]*>(.)<\/text>/
        ).compactMap { match -> Glyph? in
            guard let x = Double(match.1), let y = Double(match.2), let size = Double(match.3),
                  let ch = String(match.4).first else { return nil }
            return Glyph(x: x, y: y, size: size, character: ch)
        }
        return Page(glyphs: glyphs, systems: geometry.systems)
    }

    // MARK: - The bug as filed

    /// The reproduction in #223, in D major so the kept signature shows.
    @Test("K:bass between two lines: courtesy clef, then a bass staff in the same key")
    func asFiled() throws {
        let page = try render("K:D\nB4|\nK:bass\nD4|B,DFD|")
        try #require(page.systems.count == 2)

        // First line: the treble head, and a small F clef at its end, before the last bar.
        let first = page.glyphs(Self.clefs, inSystem: 0)
        try #require(first.count == 2)
        #expect(first[0].character == Self.gClef)
        #expect(first[1].character == Self.fClef)
        #expect(first[1].size < first[0].size)
        let lastBar = try #require(page.systems[0].barlineXs.max())
        #expect(first[1].x < lastBar)
        #expect(first[1].x > page.headsX(inSystem: 0).max() ?? 0)

        // Second line: one full-size F clef, D major's two sharps, the notes on bass lines.
        let second = page.glyphs(Self.clefs, inSystem: 1)
        #expect(second.map(\.character) == [Self.fClef])
        #expect(second.first?.size == first[0].size)
        #expect(page.glyphs([Self.sharp], inSystem: 1).count == 2)
        // D above the staff on a ledger line, B, in the top space, then D F D.
        #expect(page.headPositions(inSystem: 1) == [11, 9, 11, 13, 11])
    }

    @Test("[K:clef=bass] and K:bass draw the same thing", arguments: ["[K:clef=bass]", "K:clef=bass"])
    func otherSpellings(field: String) throws {
        let separator = field.hasPrefix("[") ? "" : "\n"
        let page = try render("K:D\nB4|\n\(field)\(separator)D4|B,DFD|")
        try #require(page.systems.count == 2)
        #expect(page.headPositions(inSystem: 1) == [11, 9, 11, 13, 11])
    }

    // MARK: - Within a line

    /// abcm2ps draws a change written after a bar line *before* it, and one in the middle of
    /// a bar between the notes.  The notes before each change stay on the clef they were
    /// written against.
    @Test("A change on a line is drawn small: before the bar line, or between the notes")
    func withinALine() throws {
        let page = try render("K:D\nB4 | [K:bass] D4 | B,2 [K:treble] B2 |")
        try #require(page.systems.count == 1)

        let clefs = page.glyphs(Self.clefs, inSystem: 0)
        #expect(clefs.map(\.character) == [Self.gClef, Self.fClef, Self.gClef])
        #expect(clefs.dropFirst().allSatisfy { $0.size < clefs[0].size })

        // B on the treble middle line, D above the bass staff, B, in its top space, B on the
        // treble middle line again.
        #expect(page.headPositions(inSystem: 0) == [4, 11, 9, 4])

        // The bass clef stands before the first bar line, the treble one between the notes.
        let bars = page.systems[0].barlineXs.sorted()
        let heads = page.headsX(inSystem: 0)
        try #require(bars.count >= 2 && heads.count == 4)
        #expect(clefs[1].x > heads[0] && clefs[1].x < bars[0])
        #expect(clefs[2].x > heads[2] && clefs[2].x < heads[3])
    }

    @Test("A change of clef alone draws no key signature where it happens")
    func noSignatureForClefAlone() throws {
        let page = try render("K:D\nB4 | [K:bass] D4 |")
        // The head's two sharps and nothing else.
        #expect(page.glyphs([Self.sharp], inSystem: 0).count == 2)
    }

    @Test("A key change after a clef change is drawn for the new clef")
    func keyChangeOnNewClef() throws {
        let page = try render("K:C\nC4 | [K:bass] D,4 | [K:G] G,4 |")
        let sharps = page.glyphs([Self.sharp], inSystem: 0)
        try #require(sharps.count == 1)
        let system = page.systems[0]
        // F♯ in the bass clef sits on the fourth line: staff position 6.
        #expect(Int(((system.bottomY - sharps[0].y) / (system.staffLineGap / 2)).rounded()) == 6)
    }

    // MARK: - More than one voice

    @Test("Each staff changes clef on its own")
    func perStaff() throws {
        let page = try render("""
            K:G
            V:1
            d4 | [K:bass] D,4 |
            V:2 clef=bass
            G,,4 | [K:clef=alto] G4 |
            """)
        // The geometry reads each staff as a system of its own; the clefs are all that matter.
        let clefs = page.glyphs.filter { Self.clefs.contains($0.character) }
        let small = clefs.filter { $0.size < (clefs.map(\.size).max() ?? 0) }
        #expect(Set(small.map(\.character)) == [Self.fClef, Self.cClef])
    }
}
