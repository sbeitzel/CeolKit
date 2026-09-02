import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #58: a tune's voices are the staves of one system, not a run of systems one after
/// the other.  These go end to end — source in, SVG out, geometry read back — because the
/// bug was only visible in the shape of the finished page.
@Suite struct MultiVoiceSystemTests {

    private func render(_ abc: String,
                        config: SVGRenderConfig = SVGRenderConfig())
    -> (pages: [PageGeometry], diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config).render(score, diagnostics: &diagnostics)
        return (try! SVGGeometry.pages(from: svgs), diagnostics)
    }

    /// Two voices, two source lines each, four bars per line.
    private let twoVoices = """
        X:1
        T:Two Voices
        M:4/4
        L:1/8
        K:D
        V:M1
        V:M2
        [V:M1] abcd efga | bage dcBA | abcd efga | bage dcBA |
        [V:M2] ABcd efga | bage dcBA | ABcd efga | bage dcBA |
        [V:M1] abcd efga | bage dcBA | abcd efga | bage dcBA |
        [V:M2] ABcd efga | bage dcBA | ABcd efga | bage dcBA |
        """

    // Two source lines × two voices = two systems of two staves, not four systems in a row.
    @Test func voicesAreStavesOfOneSystem() {
        let staves = render(twoVoices).pages.flatMap(\.systems)
        #expect(staves.count == 4)
        // Staves 0/1 are one system and 2/3 another: each pair shares an x-range, and the
        // pair sits closer together than the two pairs do.
        #expect(staves[0].left == staves[1].left && staves[0].right == staves[1].right)
        #expect(staves[2].left == staves[3].left && staves[2].right == staves[3].right)
        let withinGroup = staves[1].topY - staves[0].topY
        let betweenGroups = staves[2].topY - staves[1].topY
        #expect(withinGroup < betweenGroups)
    }

    // The bar lines of a system land on the same x on every staff — the point of writing
    // two voices in parallel is being able to read down the page.
    @Test func barLinesAlignAcrossTheStavesOfASystem() {
        let staves = render(twoVoices).pages.flatMap(\.systems)
        #expect(staves[0].barlineXs == staves[1].barlineXs)
        #expect(staves[2].barlineXs == staves[3].barlineXs)
        #expect(!staves[0].barlineXs.isEmpty)
    }

    // The scroll-sync anchors run forward down the page instead of restarting when the
    // second voice begins (issue #41's consumer breaks on a non-monotonic sequence).
    @Test func anchorLinesAreMonotonic() {
        let lines = render(twoVoices).pages.flatMap(\.systems).compactMap(\.abcLine)
        #expect(lines.count == 4)
        #expect(zip(lines, lines.dropFirst()).allSatisfy { $0 <= $1 })
        // Both staves of a system report the system's line, so consumers filtering for a
        // strictly increasing sequence keep exactly one anchor per system.
        #expect(lines[0] == lines[1])
        #expect(lines[2] == lines[3])
        #expect(lines[0] < lines[2])
    }

    // MARK: - Disagreeing voices

    // A voice short of a measure is padded rather than laid out on its own, and the render
    // says so.
    @Test func voicesOfUnequalLengthArePaddedAndWarned() {
        let abc = """
            X:1
            T:Ragged
            M:4/4
            L:1/8
            K:D
            V:M1
            V:M2
            [V:M1] abcd efga | bage dcBA | abcd efga |
            [V:M2] ABcd efga | bage dcBA |
            """
        let (pages, diagnostics) = render(abc)
        let staves = pages.flatMap(\.systems)
        #expect(staves.count == 2)
        // The short voice still gets the third measure's bar line: the staff is drawn,
        // it just has nothing in it.
        #expect(staves[0].barlineXs == staves[1].barlineXs)

        let warning = diagnostics.first { $0.code == .voiceLengthMismatch }
        #expect(warning != nil)
        #expect(warning?.severity == .warning)
        #expect(warning?.message.contains("M2") == true)
    }

    // A voice that supplied no music at all for a source line still gets a staff there.
    @Test func voiceMissingAWholeLineIsPadded() {
        let abc = """
            X:1
            T:Missing Line
            M:4/4
            L:1/8
            K:D
            V:M1
            V:M2
            [V:M1] abcd efga | bage dcBA |
            [V:M2] ABcd efga | bage dcBA |
            [V:M1] abcd efga | bage dcBA |
            """
        let (pages, diagnostics) = render(abc)
        let staves = pages.flatMap(\.systems)
        #expect(staves.count == 4)
        #expect(staves[2].barlineXs == staves[3].barlineXs)
        #expect(diagnostics.contains { $0.code == .voiceLengthMismatch })
    }

    // Voices that agree need no warning — the common case must stay quiet.
    @Test func agreeingVoicesProduceNoDiagnostic() {
        #expect(render(twoVoices).diagnostics.isEmpty)
    }

    // MARK: - Declared but unused voices — issue #61

    // A voice a `V:` declared and the body never wrote to is in the model so a `%%score`
    // plan can name it, but it has no music, so it is not engraved.  If it reached the
    // aligner it would be padded with invisible rests on every line and draw a whole staff
    // of silence — plus a mismatch warning for music the author never wrote.
    @Test func declaredButUnusedVoiceIsNotDrawn() {
        let abc = """
            X:1
            T:Two Voices
            M:4/4
            L:1/8
            K:D
            V:M1
            V:M2
            V:M3
            [V:M1] abcd efga | bage dcBA | abcd efga | bage dcBA |
            [V:M2] ABcd efga | bage dcBA | ABcd efga | bage dcBA |
            [V:M1] abcd efga | bage dcBA | abcd efga | bage dcBA |
            [V:M2] ABcd efga | bage dcBA | ABcd efga | bage dcBA |
            """
        let (pages, diagnostics) = render(abc)
        let staves = pages.flatMap(\.systems)
        // The same page `twoVoices` produces: two systems of two staves, not three, and
        // laid out identically — the unused voice costs no vertical space either.
        let expected = render(twoVoices).pages.flatMap(\.systems)
        #expect(staves.count == 4)
        #expect(staves.map(\.topY) == expected.map(\.topY))
        #expect(diagnostics.isEmpty)
    }

    // MARK: - Single voice

    // One voice is one staff per system, with no group furniture and nothing to warn about.
    @Test func singleVoiceIsUnchanged() {
        let abc = """
            X:1
            T:One Voice
            M:4/4
            L:1/8
            K:D
            abcd efga | bage dcBA |
            abcd efga | bage dcBA |
            """
        let (pages, diagnostics) = render(abc)
        #expect(pages.flatMap(\.systems).count == 2)
        #expect(diagnostics.isEmpty)
    }
}
