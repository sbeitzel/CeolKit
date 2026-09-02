import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #77: two voices on one staff (§11.1 `%%score ( … )`) are drawn as two parts —
/// stems opposed by voice position rather than chosen from each note's pitch, and
/// simultaneous rests moved off centre so they do not land on top of each other.
///
/// End to end, source in and SVG out, for the same reason ``StemDirectionTests`` is: the
/// question is what got *drawn*, and every intermediate answer was already right before the
/// fix — the merge pass (#76) had the voices in one event stream and tagged (#75), and the
/// emitter still read the pitch.
///
/// Note collisions between the two voices — unisons, seconds, displaced dots — are
/// ``SharedStaffCollisionTests``' (#79), not this suite's.  The tunes here keep the parts an
/// octave or more apart, so nothing asserted below depends on what the collision pass does.
@Suite("Shared staff: opposed stems and offset rests")
struct SharedStaffVoiceDrawingTests {

    private let config = SVGRenderConfig()

    private func svg(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
    }

    /// Two voices, one staff, over the notes given.  `c d e f` sits above the middle line,
    /// where the pitch rule stems *down*, and `C D E F` below it, where it stems *up* — so
    /// on this staff both voices are a flip away from what pitch alone would draw, and an
    /// assertion that passes cannot be passing by accident.
    private func sharedStaff(upper: String = "c d e f", lower: String = "C D E F",
                             upperVoice: String = "", lowerVoice: String = "",
                             plan: String = "%%score (T1 T2)") -> String {
        ([
            "X:1", "T:Shared", "M:4/4", "L:1/4", plan, "K:C",
            "V:T1 \(upperVoice)", "V:T2 \(lowerVoice)",
            "[V:T1] \(upper) |", "[V:T2] \(lower) |"
        ] as [String]).map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n") + "\n"
    }

    // MARK: - Stems

    @Test("A shared staff stems its upper voice up and its lower voice down, against pitch")
    func sharedStaffOpposesStems() throws {
        let metadata = try BravuraMetadata.load()
        let stems = probedStemsByPitchGroup(in: try svg(sharedStaff()),
                                            staffSize: config.staffSize, metadata: metadata,
                                            bucketCount: 2)
        try #require(stems.count == 2)
        try #require(stems[0].count == 4)
        try #require(stems[1].count == 4)
        #expect(stems[0].allSatisfy { $0.isUp })
        #expect(stems[1].allSatisfy { !$0.isUp })
    }

    @Test("The opposition holds whichever side of the middle line the parts sit on")
    func oppositionIgnoresPitchEntirely() throws {
        // Both parts high, then both parts low: the pitch rule would stem the whole staff
        // one way each time, and the opposition still splits it.
        let metadata = try BravuraMetadata.load()
        for (upper, lower) in [("c' b a g", "c d e f"), ("C D E F", "C, D, E, F,")] {
            let stems = probedStemsByPitchGroup(in: try svg(sharedStaff(upper: upper, lower: lower)),
                                                staffSize: config.staffSize, metadata: metadata,
                                                bucketCount: 2)
            try #require(stems.count == 2)
            try #require(stems[0].count == 4)
            try #require(stems[1].count == 4)
            #expect(stems[0].allSatisfy { $0.isUp })
            #expect(stems[1].allSatisfy { !$0.isUp })
        }
    }

    @Test("V: stem= on the lower voice overrides the opposition")
    func voiceStemOverridesOpposition() throws {
        let metadata = try BravuraMetadata.load()
        let stems = probedStemsByPitchGroup(in: try svg(sharedStaff(lowerVoice: "stem=up")),
                                            staffSize: config.staffSize, metadata: metadata,
                                            bucketCount: 2)
        try #require(stems.count == 2)
        try #require(stems[1].count == 4)
        // The upper voice is unchanged; the lower one now points the same way it does.
        #expect(stems[0].allSatisfy { $0.isUp })
        #expect(stems[1].allSatisfy { $0.isUp })
    }

    @Test("Separate staves keep the pitch rule — the opposition is the shared staff's alone")
    func separateStavesAreUntouched() throws {
        let metadata = try BravuraMetadata.load()
        // The same two voices, planned onto a staff each.  Both parts sit above the middle
        // line of their own staff, so the pitch rule stems both down — which is exactly what
        // the shared-staff test above proves does *not* happen when they share one.
        let stems = probedStemsByPitchGroup(in: try svg(sharedStaff(lower: "c d e f",
                                                                    plan: "%%score T1 T2")),
                                            staffSize: config.staffSize, metadata: metadata,
                                            bucketCount: 2)
        try #require(stems.count == 2)
        try #require(stems.allSatisfy { $0.count == 4 })
        #expect(stems.flatMap { $0 }.allSatisfy { !$0.isUp })
    }

    // MARK: - Rests

    /// The y of every rest glyph drawn, in the order they appear.
    private func restYs(in svg: String) -> [Double] {
        let rests: Set<Character> = [SMuFLGlyph.restWhole.character, SMuFLGlyph.restHalf.character,
                                     SMuFLGlyph.restQuarter.character, SMuFLGlyph.rest8th.character,
                                     SMuFLGlyph.rest16th.character, SMuFLGlyph.rest32nd.character,
                                     SMuFLGlyph.rest64th.character]
        return svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match in
            guard let y = Double(match.2), let ch = String(match.3).first,
                  rests.contains(ch) else { return nil }
            return y
        }
    }

    /// The y of the staff's middle line — where a rest sits when nothing displaces it.
    ///
    /// The staff lines are the five widest horizontal `<line>`s in the document: they run
    /// the length of the system, and the only other horizontal lines drawn here are ledger
    /// lines, which are a notehead wide.
    private func middleLineY(in svg: String) throws -> Double {
        let horizontals = svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { match -> (y: Double, width: Double)? in
            guard let x1 = Double(match.1), let y1 = Double(match.2),
                  let x2 = Double(match.3), let y2 = Double(match.4), y1 == y2 else { return nil }
            return (y1, x2 - x1)
        }
        let systemWidth = try #require(horizontals.map(\.width).max())
        let staffLines = horizontals.filter { $0.width == systemWidth }.map(\.y).sorted()
        try #require(staffLines.count == 5)
        return staffLines[2]
    }

    @Test("Two voices resting at one onset are drawn a staff space either side of centre")
    func simultaneousRestsAreSeparated() throws {
        let document = try svg(sharedStaff(upper: "c z c z", lower: "C z C z"))
        let ys = restYs(in: document).sorted()
        try #require(ys.count == 4)
        let middle = try middleLineY(in: document)
        // Two above centre and two below, each by one staff space: the upper voice's rests
        // rise and the lower voice's fall, so they never coincide.
        #expect(ys[0] == middle - config.staffSize)
        #expect(ys[1] == middle - config.staffSize)
        #expect(ys[2] == middle + config.staffSize)
        #expect(ys[3] == middle + config.staffSize)
    }

    @Test("A bar whose partner voice is invisible keeps its rest centred")
    func restStaysCentredWhereOnlyOneVoiceIsDrawn() throws {
        // `x` is a rest that occupies the bar without being drawn (§4.9), which is how the
        // §7 Zocharti Loch example writes a part that has not entered yet.  Nothing is there
        // to collide with, so nothing moves — and `abcm2ps -g` draws those bars the same way.
        let document = try svg(sharedStaff(upper: "c z c z", lower: "x4"))
        let ys = restYs(in: document)
        try #require(ys.count == 2)
        let middle = try middleLineY(in: document)
        #expect(ys.allSatisfy { $0 == middle })
    }

    @Test("A staff with one voice rests on the middle line, as it always has")
    func singleVoiceRestIsUnmoved() throws {
        let document = try svg("X:1\nT:Alone\nM:4/4\nL:1/4\nK:C\nc z c z |\n")
        let ys = restYs(in: document)
        try #require(ys.count == 2)
        let middle = try middleLineY(in: document)
        #expect(ys.allSatisfy { $0 == middle })
    }
}
