import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #134: the key signature repeated at the head of every system is the key that system
/// *opens in*, not the one the voice opened the tune in.
///
/// #129 made a body `K:` draw the change where it happens; the signature that then stands for
/// the rest of the tune was still resolved once per voice, so every system after a mid-tune
/// change drew the old key — or, where the old key had no accidentals, nothing at all.
///
/// Where a system opens *on* the measure the change lands on, the two meet: the head draws the
/// change — cancelling naturals included — and the bar draws nothing, so it is engraved once.
@Suite("A system's head draws the key it opens in")
struct SystemHeadKeySignatureTests {

    /// Every SMuFL glyph the page draws, as `(character, x, y)`.  `<text>` carries each run's
    /// position in attributes rather than a transform, which is what makes it the probe.
    private func glyphs(_ svg: String) -> [(char: Character, x: Double, y: Double)] {
        var found: [(Character, Double, Double)] = []
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard let close = segment.range(of: ">"),
                  let end = segment.range(of: "</text>") else { continue }
            let attrs = segment[segment.startIndex..<close.lowerBound]
            let body  = segment[close.upperBound..<end.lowerBound]
            guard let char = body.first, char.unicodeScalars.first!.value > 0xE000 else { continue }
            guard let x = attribute("x", in: attrs), let y = attribute("y", in: attrs) else { continue }
            found.append((char, x, y))
        }
        return found
    }

    private func attribute(_ name: String, in attrs: Substring) -> Double? {
        guard let start = attrs.range(of: "\(name)=\"") else { return nil }
        let rest = attrs[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return Double(rest[rest.startIndex..<end])
    }

    private func page(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try textProbeRenderer().render(score)
        return try #require(pages.first)
    }

    /// The glyphs of one staff system, keyed by the clef's y — one system per staff head, and
    /// every glyph of a system shares its band.  Returned top to bottom.
    private func systems(_ svg: String) -> [[(char: Character, x: Double, y: Double)]] {
        let drawn = glyphs(svg)
        let clefYs = drawn.filter { $0.char == SMuFLGlyph.gClef.character }
            .map(\.y).sorted()
        return clefYs.enumerated().map { i, clefY in
            let upper = i + 1 < clefYs.count ? (clefY + clefYs[i + 1]) / 2 : Double.infinity
            let lower = i == 0 ? -Double.infinity : (clefYs[i - 1] + clefY) / 2
            return drawn.filter { $0.y > lower && $0.y < upper }.sorted { $0.x < $1.x }
        }
    }

    /// The accidentals drawn at `system`'s head — between the clef and its first notehead.
    private func headAccidentals(_ system: [(char: Character, x: Double, y: Double)]) -> [Character] {
        guard let clefX = system.first(where: { $0.char == SMuFLGlyph.gClef.character })?.x,
              let firstNoteX = system.first(where: {
                  $0.char == SMuFLGlyph.noteheadBlack.character
              })?.x else { return [] }
        return system.filter { $0.x > clefX && $0.x < firstNoteX }
            .map(\.char)
            .filter { $0 == SMuFLGlyph.accidentalSharp.character
                   || $0 == SMuFLGlyph.accidentalFlat.character
                   || $0 == SMuFLGlyph.accidentalNatural.character }
    }

    /// The issue's own source: three systems, the `K:D` landing at the head of the second.
    private let threeSystems = """
        X:1
        T:Key change, three systems
        M:4/4
        L:1/4
        K:C
        CDEF|CDEF|
        K:D
        DEFG|DEFG|
        DEFG|DEFG|
        """

    // MARK: The bug

    @Test("Every system after the change draws the new signature")
    func laterSystemsDrawTheNewKey() throws {
        let rows = systems(try page(threeSystems))
        try #require(rows.count == 3)

        let sharp = SMuFLGlyph.accidentalSharp.character
        #expect(headAccidentals(rows[0]).isEmpty, "C major draws none")
        #expect(headAccidentals(rows[1]) == [sharp, sharp], "the system the K:D lands on")
        #expect(headAccidentals(rows[2]) == [sharp, sharp],
                "and every system after it, which is the bug #134 reported")
    }

    @Test("The change is drawn once, in the head, not again in the bar")
    func theOpeningSystemDrawsItOnlyOnce() throws {
        let rows = systems(try page(threeSystems))
        try #require(rows.count == 3)

        let sharps = rows[1].filter { $0.char == SMuFLGlyph.accidentalSharp.character }
        #expect(sharps.count == 2, "two sharps on the system the change opens, not four")
        let firstNoteX = try #require(rows[1].first {
            $0.char == SMuFLGlyph.noteheadBlack.character
        }?.x)
        #expect(sharps.allSatisfy { $0.x < firstNoteX }, "both stand in the head")
    }

    @Test("A head that opens on the change cancels the signature it leaves behind")
    func theOpeningHeadCancelsTheOutgoingKey() throws {
        // E♭ major (B♭ E♭ A♭) to C major across a source line break: the new key writes
        // nothing, so the head of the second system is three naturals and no more.
        let rows = systems(try page("""
            X:1
            M:4/4
            L:1/4
            K:Eb
            EFGA|EFGA|
            K:C
            CDEF|CDEF|
            """))
        try #require(rows.count == 2)

        let flat = SMuFLGlyph.accidentalFlat.character
        let natural = SMuFLGlyph.accidentalNatural.character
        #expect(headAccidentals(rows[0]) == [flat, flat, flat])
        #expect(headAccidentals(rows[1]) == [natural, natural, natural])
        #expect(rows[1].filter { $0.char == natural }.count == 3,
                "the naturals are drawn in the head and nowhere else on the system")
    }

    // MARK: What #129 established, and must keep

    @Test("A change part way through a system is still drawn in the bar")
    func aMidSystemChangeStaysInTheBar() throws {
        let rows = systems(try page("""
            X:1
            M:4/4
            L:1/4
            K:C
            CDEF|[K:D]DEFG|
            """))
        try #require(rows.count == 1)

        #expect(headAccidentals(rows[0]).isEmpty, "the system opens in C major")
        let sharps = rows[0].filter { $0.char == SMuFLGlyph.accidentalSharp.character }
        let noteXs = rows[0].filter { $0.char == SMuFLGlyph.noteheadBlack.character }.map(\.x)
        try #require(sharps.count == 2 && noteXs.count == 8)
        #expect(sharps.allSatisfy { noteXs[3] < $0.x && $0.x < noteXs[4] })
    }

    @Test("A staff plan in the body does not reset the key the music reached")
    func aPlanRegionInheritsTheRunningKey() throws {
        // §11.1 cuts the tune into plan regions and lays each out on its own, which is a
        // system break like any other: the region after the change opens in D major, not in
        // the C major the voice was declared in.
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            V:1 clef=treble
            V:2 clef=bass
            K:C
            %%score 1 2
            V:1
            CDEF|[K:D]DEFG|
            V:2
            C,D,E,F,|D,E,F,G,|
            %%score 1
            V:1
            DEFG|DEFG|
            """)
        let drawn = glyphs(svg)

        // The last treble staff head on the page is the one the second region opens.
        let lastTrebleY = try #require(
            drawn.filter { $0.char == SMuFLGlyph.gClef.character }.map(\.y).max())
        let lastSystem = drawn.filter { $0.y == lastTrebleY || abs($0.y - lastTrebleY) < 24 }
            .sorted { $0.x < $1.x }
        #expect(headAccidentals(lastSystem) == [SMuFLGlyph.accidentalSharp.character,
                                                SMuFLGlyph.accidentalSharp.character])
    }

    // MARK: The space the head is given

    @Test("A system opening in the new key reserves the room its signature needs")
    func theHeadIsGivenRoom() throws {
        // The third system is in D major but was laid out as if it were in C: its music has
        // to start clear of the two sharps, not on top of them.
        let rows = systems(try page(threeSystems))
        try #require(rows.count == 3)

        let lastSharpX = try #require(
            rows[2].filter { $0.char == SMuFLGlyph.accidentalSharp.character }.map(\.x).max())
        let firstNoteX = try #require(rows[2].first {
            $0.char == SMuFLGlyph.noteheadBlack.character
        }?.x)
        #expect(firstNoteX > lastSharpX + 5, "a notehead's clearance past the last accidental")
    }

    @Test("The line breaker charges the head the system actually draws")
    func theBreakerChargesThePerSystemHead() throws {
        // Every system of this tune is packed by the breaker rather than the source, and each
        // one after the first is in C♯ major — seven sharps, the widest head there is.  A
        // breaker still charging the opening key (no accidentals) would let a system take a
        // measure it has no room for, and the justifier would then compress it past the right
        // margin.  Nothing may cross it.
        let svg = try page("""
            X:1
            M:4/4
            L:1/8
            K:C
            CDEFGABc|
            K:C#
            CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|\
            CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|CDEFGABc|
            """)
        let rows = systems(svg)
        try #require(rows.count > 2, "the tune needs more systems than the source lines gave it")
        for row in rows.dropFirst() {
            #expect(headAccidentals(row).count == 7, "seven sharps at every later head")
        }
        let rightMargin = SVGRenderConfig().pageSize.width - SVGRenderConfig().margins.right
        for glyph in glyphs(svg) {
            #expect(glyph.x <= rightMargin, "no glyph may be drawn past the right margin")
        }
    }
}
