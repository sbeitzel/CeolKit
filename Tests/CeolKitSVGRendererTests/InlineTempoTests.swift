import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Tests that inline tempo changes (`[Q:...]`) produce tempo annotations
/// in the SVG output at the point of change, not just in the title block.
///
/// All tests in this suite are expected to FAIL until the fix is applied:
///   1. `Event` gains a `case tempoChange(Tempo)`.
///   2. The semantic pass emits `.tempoChange` events for inline `[Q:...]` fields
///      instead of the current `break // tempo changes not tracked per-voice in v0.1`.
///   3. `MeasureSizer` and `SVGEmitter` render a tempo annotation at that event's position.
///
/// The tests check for `"= N"` patterns (e.g. `"= 120"`) which appear only in
/// rendered tempo text like `♩ = 120` — never as an SVG attribute/coordinate value.
@Suite("Inline tempo change rendering (issue #26)")
struct InlineTempoTests {

    // MARK: - Minimal single change

    /// A tune with an inline `[Q:1/4=120]` mid-line.  The header has no Q: field,
    /// so the annotation `= 120` can only appear in the SVG if the inline change is rendered.
    @Test("Inline Q: mid-tune change: tempo annotation appears in SVG body")
    func singleInlineTempoChange() throws {
        let abc = """
            X:1
            T:Test
            M:4/4
            L:1/8
            K:C
            ABCD [Q:1/4=120] | EFGA |]
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try SVGRenderer().render(score)
        let svg = try #require(pages.first)

        // "= 120" appears in tempo text like "♩ = 120"; it cannot appear in SVG attributes.
        #expect(svg.contains("= 120"),
                "Inline [Q:1/4=120] must produce a tempo annotation containing '= 120' in the SVG")
    }

    // MARK: - Header tempo vs. inline tempo change

    /// When the header has `Q:1/4=80` and an inline `[Q:1/4=120]` changes the
    /// tempo mid-tune, both values should be visible — `= 80` in the title block
    /// area and `= 120` in the score body at the point of change.
    @Test("Header tempo and inline tempo change are both rendered")
    func headerAndInlineTempoRendered() throws {
        let abc = """
            X:1
            T:Test
            M:4/4
            L:1/8
            Q:1/4=80
            K:C
            ABCD [Q:1/4=120] | EFGA |]
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try SVGRenderer().render(score)
        let svg = try #require(pages.first)

        // "= 80" must come from the header Q: rendered in the title block (issue #26 Part 1).
        #expect(svg.contains("= 80"),
                "Header tempo Q:1/4=80 must produce '= 80' in the title block SVG")
        // "= 120" must come from the inline [Q:1/4=120] change in the score body.
        #expect(svg.contains("= 120"),
                "Inline [Q:1/4=120] must produce '= 120' in the score body SVG")
    }
}
