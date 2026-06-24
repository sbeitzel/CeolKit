import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

// MARK: - Helpers

/// Returns the Unicode scalar value for the given `SMuFLGlyph` as a `String`,
/// so we can search SVG text content without importing the glyph enum directly.
private func glyphChar(_ glyph: SMuFLGlyph) -> String {
    String(glyph.character)
}

/// Count how many times `substring` appears in `string`.
private func count(_ substring: String, in string: String) -> Int {
    var n = 0
    var search = string[...]
    while let range = search.range(of: substring) {
        n += 1
        search = search[range.upperBound...]
    }
    return n
}

// MARK: - Suite

/// Tests that inline meter changes (`[M:...]`) produce time-signature glyphs
/// in the SVG output at the point of change, not just in the system header.
///
/// All tests in this suite are expected to FAIL until the fix is applied:
///   1. `Measure` gains a `meter: Meter?` property populated by the semantic pass.
///   2. `SVGEmitter` emits a time-signature glyph before any measure whose `meter`
///      differs from the system's header meter.
///   3. `MeasureSizer` accounts for that glyph's width in the natural measure width.
@Suite("Mid-line meter change rendering")
struct MidLineMeterChangeTests {

    // MARK: Minimal single change

    /// A tune starting in 4/4 with a single `[M:6/8]` mid-line change.
    ///
    /// The system header will render 4/4 (digits 4, 4 only).
    /// After the inline change the renderer must emit a 6/8 glyph — producing
    /// `timeSig6` (U+E086) and `timeSig8` (U+E088) which are otherwise absent.
    @Test("6/8 mid-line change: glyph characters appear in SVG body")
    func singleMidLineMeterChange() throws {
        let abc = """
            X:1
            T:Test
            M:4/4
            L:1/8
            K:D
            ABCD [M:6/8] | EFG |]
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try SVGRenderer().render(score)
        let svg = try #require(pages.first)

        let six  = glyphChar(.timeSig6)
        let eight = glyphChar(.timeSig8)

        #expect(svg.contains(six),
                "timeSig6 glyph (U+E086) must appear: the [M:6/8] change should be rendered")
        #expect(svg.contains(eight),
                "timeSig8 glyph (U+E088) must appear: the [M:6/8] change should be rendered")
    }

    // MARK: Multiple changes

    /// The last system of "Bob Cooper of Winnipeg" (X:1 in tunebook.abc) has four
    /// back-to-back inline meter changes: `[M:6/4]`, `[M:4/4]`, `[M:2/4]`, `[M:6/8]`.
    ///
    /// The initial meter is 4/4, so the system header contributes exactly two `timeSig4`
    /// glyphs (numerator 4, denominator 4).  After the fix, mid-line changes must add:
    ///   • `[M:6/4]` → one more timeSig6, one more timeSig4
    ///   • `[M:4/4]` → two more timeSig4
    ///   • `[M:2/4]` → one timeSig2, one more timeSig4
    ///   • `[M:6/8]` → one more timeSig6, one timeSig8
    ///
    /// So the minimal assertions are:
    ///   - timeSig2 appears at least once (only from [M:2/4])
    ///   - timeSig6 appears at least once (only from [M:6/4] or [M:6/8])
    ///   - timeSig8 appears at least once (only from [M:6/8])
    ///   - timeSig4 appears more than twice (header gives 2; each inline 4-using sig adds more)
    @Test("Multiple mid-line changes in Bob Cooper: all changed signatures rendered")
    func bobCooperMidLineChanges() throws {
        let loader = try TuneLoader()
        let result = CeolKitParser().parse(loader.tunebook, options: .default)
        let pages = try SVGRenderer().render(result.score)

        // Bob Cooper is tune X:1; it appears on page 1.
        let svg = try #require(pages.first { $0.contains("Bob Cooper") },
                               "Page containing 'Bob Cooper of Winnipeg' not found")

        let two   = glyphChar(.timeSig2)
        let four  = glyphChar(.timeSig4)
        let six   = glyphChar(.timeSig6)
        let eight = glyphChar(.timeSig8)

        #expect(svg.contains(two),
                "timeSig2 (U+E082) must appear: [M:2/4] change should be rendered")
        #expect(svg.contains(six),
                "timeSig6 (U+E086) must appear: [M:6/4] or [M:6/8] change should be rendered")
        #expect(svg.contains(eight),
                "timeSig8 (U+E088) must appear: [M:6/8] change should be rendered")

        // Header 4/4 alone = 2 occurrences; any inline 4-bearing sig adds more.
        let fourCount = count(four, in: svg)
        #expect(fourCount > 2,
                "timeSig4 should appear more than the 2 from the system header (got \(fourCount))")
    }

    // MARK: Position: mid-line glyph is not at header x

    /// The x coordinate of a mid-line time-signature glyph must be strictly greater
    /// than the x coordinate of the system-header time signature, because it sits
    /// inside the body of the music — not at the left edge of the staff.
    ///
    /// Strategy: render `M:4/4` with `[M:6/8]` mid-line; find the x values of all
    /// `<text>` elements that contain a `timeSig6` character.  All such x values
    /// must exceed the header's time-signature x (which is clefWidth + keyWidth from
    /// the left margin, well under 100 pt for default staffSize=7).
    @Test("Mid-line glyph x position is inside the music body, not at header")
    func midLineGlyphIsNotAtHeaderPosition() throws {
        let abc = """
            X:1
            T:Test
            M:4/4
            L:1/8
            K:D
            ABCDEFGA [M:6/8] | BCD |]
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try SVGRenderer().render(score)
        let svg = try #require(pages.first)

        let six = glyphChar(.timeSig6)

        // Collect x values of all <text> elements containing timeSig6.
        var glyphXValues: [Double] = []
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard segment.contains(six) else { continue }
            guard let xRange = segment.range(of: " x=\"") else { continue }
            let after = segment[xRange.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { continue }
            if let x = Double(after[after.startIndex..<end]) {
                glyphXValues.append(x)
            }
        }

        #expect(!glyphXValues.isEmpty,
                "No <text> elements found containing timeSig6 — mid-line glyph was not emitted")

        // The system header for K:D (2 sharps) + clef fits comfortably within 100 pt
        // at staffSize=7.  A mid-line glyph must sit further right.
        let minimumBodyX = 100.0
        for x in glyphXValues {
            #expect(x > minimumBodyX,
                    "timeSig6 at x=\(x) looks like a header glyph, not a mid-line glyph")
        }
    }
}
