import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #74: a voice's `V:` `stem=up|down` decides which way its stems point, outranking
/// the document-wide `%%ceolkit:pipeformat` and the note's own staff position.
///
/// End to end — source in, SVG out — because the point of the issue was that the value was
/// parsed and then never reached the drawing.  Asserting on `VoiceProperties` would have
/// passed before the fix.
///
/// Direction is read out of the emitted document rather than out of the layout: a stem is
/// drawn from its notehead, so the end that coincides with a notehead's y is the notehead
/// end, and the stem points away from it.
@Suite("Stem direction (V: stem=)")
struct StemDirectionTests {

    /// One drawn stem, with the direction recovered from where its notehead sits.
    private struct Stem {
        let x: Double
        let noteheadY: Double
        let tipY: Double
        var isUp: Bool { tipY < noteheadY }
    }

    /// Every stem in `svg`, paired with the notehead it grows from.
    ///
    /// Stems are the `<line>`s at Bravura's stem thickness — thinner than every staff line
    /// and bar line in the document, which is what ``BravuraMetadataTests`` pins.  Noteheads
    /// are the Bravura `<text>` runs, so the renderer is driven in `.fontFace` mode to keep
    /// them readable as text.
    private func stems(in svg: String, staffSize: Double, metadata: BravuraMetadata) -> [Stem] {
        let stemWidth = metadata.engravingDefaults.stemThickness * staffSize
        let noteheads = svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match -> (x: Double, y: Double)? in
            let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                         SMuFLGlyph.noteheadHalf.character,
                                         SMuFLGlyph.noteheadWhole.character]
            guard let x = Double(match.1), let y = Double(match.2),
                  let ch = String(match.3).first, heads.contains(ch) else { return nil }
            return (x, y)
        }

        return svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { match -> Stem? in
            guard let x = Double(match.1), let y1 = Double(match.2),
                  let y2 = Double(match.4), let width = Double(match.5),
                  abs(width - stemWidth) < 0.01, y1 != y2 else { return nil }
            // The notehead end is whichever end a notehead is drawn at.  A stem is attached
            // to the right of its notehead when it points up and to the left when it points
            // down, so the x match has to allow a notehead's width either way.
            let touches: (Double) -> Bool = { end in
                noteheads.contains { abs($0.y - end) < 0.01 && abs($0.x - x) < 4 * staffSize }
            }
            if touches(y2) { return Stem(x: x, noteheadY: y2, tipY: y1) }
            if touches(y1) { return Stem(x: x, noteheadY: y1, tipY: y2) }
            return nil
        }
    }

    /// Renders `abc` and returns the stems of each staff, top staff first.
    ///
    /// Bucketed by the staff the notehead falls nearest, so a two-voice tune's staves can be
    /// asserted against each other — the whole point of "other voices unaffected".
    private func stemsPerStaff(_ abc: String, staffCount: Int) throws -> [[Stem]] {
        let metadata = try BravuraMetadata.load()
        let config = SVGRenderConfig()
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
        let all = stems(in: svg, staffSize: config.staffSize, metadata: metadata)
        // Staves are far enough apart vertically that sorting the noteheads into `staffCount`
        // clusters by y is unambiguous: every stem of a staff is nearer its own staff's notes
        // than the next staff's.
        let sorted = all.sorted { $0.noteheadY < $1.noteheadY }
        guard staffCount > 1, !sorted.isEmpty else { return [sorted.sorted { $0.x < $1.x }] }
        let perStaff = sorted.count / staffCount
        return (0..<staffCount).map { staff in
            Array(sorted[(staff * perStaff)..<((staff + 1) * perStaff)]).sorted { $0.x < $1.x }
        }
    }

    /// Two voices over the same four notes, so any difference between the staves is the
    /// `V:` attributes and nothing else.
    private func twoVoices(_ first: String, _ second: String = "",
                           directive: String = "", notes: String = "c d e f") -> String {
        ([
            "X:1", "T:Stems", "M:4/4", "L:1/4", directive, "K:C",
            "V:1 \(first)", "V:2 \(second)",
            "[V:1] \(notes) |", "[V:2] \(notes) |"
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
    }

    // MARK: - The voice's own stem=

    @Test("stem=up forces every stem up regardless of pitch, and leaves other voices alone")
    func stemUpForcesUpAndIsVoiceLocal() throws {
        // c d e f sit above the middle line, where the pitch rule stems down — which is what
        // voice 2 does.  Every assertion here is a flip away from the untouched control.
        let staves = try stemsPerStaff(twoVoices("stem=up"), staffCount: 2)
        try #require(staves.count == 2)
        try #require(staves[0].count == 4)
        try #require(staves[1].count == 4)
        #expect(staves[0].allSatisfy { $0.isUp })
        #expect(staves[1].allSatisfy { !$0.isUp })
    }

    @Test("stem=down forces every stem down regardless of pitch")
    func stemDownForcesDown() throws {
        // C D E F sit below the middle line, where the pitch rule stems *up* — so voice 2 is
        // the control that says the forced staff is not simply agreeing with the default.
        let staves = try stemsPerStaff(twoVoices("stem=down", notes: "C D E F"), staffCount: 2)
        try #require(staves.count == 2)
        try #require(staves[0].count == 4)
        try #require(staves[1].count == 4)
        #expect(staves[0].allSatisfy { !$0.isUp })
        #expect(staves[1].allSatisfy { $0.isUp })
    }

    // MARK: - Against the document

    @Test("%%ceolkit:pipeformat true still stems a voice that asks for nothing down")
    func pipeFormatStillGoverns() throws {
        // Low notes, which the pitch rule would stem up — so the directive is doing the work.
        let staves = try stemsPerStaff(twoVoices("", directive: "%%ceolkit:pipeformat true",
                                                 notes: "C D E F"),
                                       staffCount: 2)
        try #require(staves.flatMap { $0 }.count == 8)
        #expect(staves.flatMap { $0 }.allSatisfy { !$0.isUp })
    }

    @Test("A voice with stem=up under pipeformat gets up stems — the voice wins")
    func voiceOutranksPipeFormat() throws {
        // Low notes again: voice 2 is stemmed down by the directive against the pitch rule,
        // so both staves differ from what they would draw on their own and from each other.
        let staves = try stemsPerStaff(twoVoices("stem=up", directive: "%%ceolkit:pipeformat true",
                                                 notes: "C D E F"),
                                       staffCount: 2)
        try #require(staves.count == 2)
        try #require(staves[0].count == 4)
        try #require(staves[1].count == 4)
        #expect(staves[0].allSatisfy { $0.isUp })
        #expect(staves[1].allSatisfy { !$0.isUp })
    }

    /// One voice, so the stems come back in written order with nothing to bucket.
    private func oneVoice(_ notes: String) -> String {
        "X:1\nT:Stems\nM:4/4\nL:1/4\nK:C\n\(notes) |\n"
    }

    // MARK: - Nobody asks

    @Test("With neither, the note's own staff position still decides")
    func autoFallsBackToPitch() throws {
        let staves = try stemsPerStaff(oneVoice("C D E F G a b c'"), staffCount: 1)
        let stems = try #require(staves.first)
        try #require(stems.count == 8)
        // At or below the middle line up, above it down — C4…G4 against A5…C6.  The rule the
        // emitter has always applied, left untouched by the fix.
        #expect(stems.prefix(5).allSatisfy { $0.isUp })
        #expect(stems.suffix(3).allSatisfy { !$0.isUp })
    }

    @Test("An explicit stem=auto draws exactly what stating nothing draws")
    func explicitAutoIsNotADifference() throws {
        let score = { (abc: String) in CeolKitParser().parse(abc, options: .default).score }
        var diagnostics: [Diagnostic] = []
        let bare = try textProbeRenderer().render(score(twoVoices("")), diagnostics: &diagnostics)
        let auto = try textProbeRenderer().render(score(twoVoices("stem=auto")), diagnostics: &diagnostics)
        #expect(bare == auto)
    }
}
