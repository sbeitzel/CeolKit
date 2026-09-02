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

    /// Renders `abc` and returns the stems of each staff, top staff first.
    ///
    /// Bucketed by pitch, which separates the staves of these tunes exactly: they are far
    /// enough apart vertically that every stem of a staff is nearer its own staff's notes
    /// than the next staff's.  See ``probedStemsByPitchGroup(in:staffSize:metadata:bucketCount:)``.
    private func stemsPerStaff(_ abc: String, staffCount: Int) throws -> [[ProbedStem]] {
        let metadata = try BravuraMetadata.load()
        let config = SVGRenderConfig()
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
        return probedStemsByPitchGroup(in: svg, staffSize: config.staffSize, metadata: metadata,
                                       bucketCount: staffCount)
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
