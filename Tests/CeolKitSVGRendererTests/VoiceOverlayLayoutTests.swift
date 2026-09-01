import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #81: the `&` voice overlay of §7.4, drawn through the shared-staff machinery built
/// for `%%score ( … )`.
///
/// An overlay is a further tenant of the staff its voice is already on, so nothing below
/// ``OverlayExpander`` needs to know it exists — the merge onto a common onset grid (#76),
/// the opposed stems (#77), the per-voice arcs (#78) and the displaced heads (#79) all apply
/// unchanged.  What these assert is that it really does arrive there: one staff, three parts
/// on it, sharing columns and opposing stems.
@Suite("& voice overlay: laid out on one staff")
struct VoiceOverlayLayoutTests {

    private let config = SVGRenderConfig()

    private func svg(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
    }

    /// The standard's own §7.4 example: one bar, then a bar carrying three overlaid parts.
    private let specExample = """
    X:1
    T:Overlay
    M:6/8
    L:1/8
    K:C
    A2 | cdefga &\\
         AAAAAA &\\
         FEDCB,A, |]
    """

    // MARK: - Probes

    /// Every notehead drawn, as (x, y).
    private func noteheads(in svg: String) -> [(x: Double, y: Double)] {
        svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match in
            let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                         SMuFLGlyph.noteheadHalf.character,
                                         SMuFLGlyph.noteheadWhole.character]
            guard let x = Double(match.1), let y = Double(match.2),
                  let ch = String(match.3).first, heads.contains(ch) else { return nil }
            return (x, y)
        }
    }

    /// How many staves the document draws, counted from the five-line groups.
    private func staffCount(in svg: String) -> Int {
        let lines = svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { match -> (y: Double, span: Double)? in
            guard let x1 = Double(match.1), let y1 = Double(match.2), let x2 = Double(match.3),
                  let y2 = Double(match.4), y1 == y2 else { return nil }
            return (y1, x2 - x1)
        }
        guard let widest = lines.map(\.span).max() else { return 0 }
        return lines.filter { $0.span == widest }.count / 5
    }

    // MARK: - One staff, three parts

    @Test("§7.4: two &s put three parts on one staff, not three staves")
    func overlaidPartsShareAStaff() throws {
        let svg = try svg(specExample)
        #expect(staffCount(in: svg) == 1)
        // A2, then three parts of six eighths each.
        #expect(noteheads(in: svg).count == 19)
    }

    @Test("The three parts sound together, so they share six columns")
    func partsShareTheirColumns() throws {
        let heads = noteheads(in: try svg(specExample))
        // The opening bar's single note is the leftmost; the overlaid bar is everything to
        // the right of it, and its heads stand in six columns of three.
        let opening = try #require(heads.map(\.x).min())
        let overlaid = heads.filter { $0.x > opening + 1 }
        let columns = Set(overlaid.map { ($0.x * 100).rounded() })
        #expect(columns.count == 6)
        #expect(overlaid.count == 18)
    }

    @Test("The staff opposes the outer parts' stems, as a ( … ) group's are opposed")
    func stemsAreOpposed() throws {
        let metadata = try BravuraMetadata.load()
        // The overlaid bar alone, so the three parts do not cross and the pitch buckets are
        // exactly the parts.  Every note of the middle part sits between the outer two.
        let stems = probedStemsByPitchGroup(
            in: try svg("X:1\nM:6/8\nL:1/8\nK:C\ncdefga & AAAAAA & FEDCB,A, |]\n"),
            staffSize: config.staffSize, metadata: metadata, bucketCount: 3)
        try #require(stems.count == 3)
        // Highest part up, lowest down; the middle one keeps the pitch rule (#77).
        #expect(stems[0].allSatisfy { $0.isUp })
        #expect(stems[2].allSatisfy { !$0.isUp })
    }

    @Test("An & overlay draws the page the equivalent ( … ) group draws")
    func overlayMatchesTheGroupThatSaysTheSameThing() throws {
        // The whole claim of #81 in one assertion: `&` is routed through the machinery
        // §11.1 already had, so the two spellings of three parts on one staff cannot
        // disagree about anything — columns, beams, stems, bar lines or page.
        let metadata = try BravuraMetadata.load()
        let overlaid = try svg("""
        X:1
        M:6/8
        L:1/8
        K:C
        cdefga & AAAAAA & FEDCB,A, |]
        """)
        let grouped = try svg("""
        X:1
        M:6/8
        L:1/8
        %%score (T1 T2 T3)
        K:C
        V:T1
        V:T2
        V:T3
        [V:T1] cdefga |]
        [V:T2] AAAAAA |]
        [V:T3] FEDCB,A, |]
        """)
        // Everything the music draws, not the whole document: the two sources sit on
        // different lines of their files, and the scroll-sync anchor says so.
        func drawn(_ svg: String) -> ([String], [String]) {
            (noteheads(in: svg).map { "\($0.x),\($0.y)" }.sorted(),
             probedStems(in: svg, staffSize: config.staffSize, metadata: metadata)
                 .map { "\($0.x),\($0.noteheadY),\($0.tipY)" }.sorted())
        }
        let (heads, stems) = drawn(overlaid)
        try #require(heads.count == 18)
        try #require(stems.count == 18)
        #expect(heads == drawn(grouped).0)
        #expect(stems == drawn(grouped).1)
    }

    // MARK: - The expansion itself

    @Test("A voice with overlays becomes that many voices, all on its own staff")
    func selectorPutsEveryLayerOnTheOneStaff() {
        let score = CeolKitParser().parse(specExample, options: .default).score
        var diagnostics: [Diagnostic] = []
        let selection = VoiceSelector.select(from: score.tunes[0].voices, plan: nil,
                                             into: &diagnostics)
        #expect(selection.staffCount == 1)
        #expect(selection.voices.count == 3)
        #expect(selection.staffOfVoice == [0, 0, 0])
        // Every layer is the voice it overlays, so it answers to the same name, key and clef.
        let ids = Set(selection.voices.map(\.id))
        #expect(ids == [.named("1")])
    }

    @Test("An overlay stays on its voice's staff when a %%score plan places that voice")
    func overlaysSurviveAStaffPlan() {
        let score = CeolKitParser().parse("""
        X:1
        M:4/4
        L:1/4
        %%score [T1 T2]
        K:C
        V:T1
        V:T2
        [V:T1] cdef & CDEF |
        [V:T2] GABc |
        """, options: .default).score
        var diagnostics: [Diagnostic] = []
        let tune = score.tunes[0]
        let plan = tune.staffPlans.last { $0.effectiveFromStave == 0 }?.plan
        let selection = VoiceSelector.select(from: tune.voices, plan: plan, into: &diagnostics)
        // Two staves still: T1's overlay joins T1, and T2 is left alone.
        #expect(selection.staffCount == 2)
        #expect(selection.staffOfVoice == [0, 0, 1])
        let ids: [VoiceId] = selection.voices.map(\.id)
        #expect(ids == [.named("T1"), .named("T1"), .named("T2")])
    }

    @Test("A tune with no & is selected exactly as it was")
    func nothingChangesWithoutAnOverlay() {
        let score = CeolKitParser().parse("""
        X:1
        M:4/4
        L:1/4
        K:C
        cdef | gabc' |
        """, options: .default).score
        var diagnostics: [Diagnostic] = []
        let selection = VoiceSelector.select(from: score.tunes[0].voices, plan: nil,
                                             into: &diagnostics)
        #expect(selection.voices.count == 1)
        #expect(selection.staffOfVoice == [0])
        #expect(diagnostics.isEmpty)
    }

    @Test("A layer silent on a whole stave is still that stave's layer, and warns about nothing")
    func aSilentStaveIsPaddedNotMisaligned() throws {
        // The overlay is written on the first line only; the second line has none.  The
        // aligner must not see a voice that is a stave short.
        let score = CeolKitParser().parse("""
        X:1
        M:4/4
        L:1/4
        K:C
        cdef & CDEF |
        gabc' |
        """, options: .default).score
        var diagnostics: [Diagnostic] = []
        let selection = VoiceSelector.select(from: score.tunes[0].voices, plan: nil,
                                             into: &diagnostics)
        let aligned = VoiceAligner.align(selection.voices, into: &diagnostics)
        #expect(aligned.count == 2)
        #expect(aligned.allSatisfy { $0.measures.allSatisfy { $0.count == 1 } })
        #expect(!diagnostics.contains { $0.code == .voiceLengthMismatch })
    }
}
