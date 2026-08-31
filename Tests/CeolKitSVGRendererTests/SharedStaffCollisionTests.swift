import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #79: what two voices sharing a staff (§11.1 `%%score ( … )`) draw where their notes
/// land on the same spot.
///
/// The merge (#76) puts every voice sounding at one onset at one x, which is what makes a
/// shared staff readable as two parts and what makes its noteheads collide: a unison writes
/// two heads over each other, a second writes two heads that half overlap, and the dots and
/// accidentals of both hang in the same strip of air.
///
/// End to end, source in and SVG out, like ``SharedStaffVoiceDrawingTests`` and
/// ``SharedStaffArcAndBeamTests``: the question is what got *drawn*, and the layout it was
/// drawn from was already right.  The expected geometry is `abcm2ps -g`'s, checked against it
/// case by case — except where this deliberately parts company, which is called out where it
/// happens.
@Suite("Shared staff: notehead collisions")
struct SharedStaffCollisionTests {

    private let config = SVGRenderConfig()

    private func svg(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
    }

    /// A two-voice tune, both voices on one staff unless `plan` says otherwise.
    private func tune(_ upper: String, _ lower: String, unitLength: String = "1/4",
                      plan: String = "%%score (T1 T2)") -> String {
        ["X:1", "T:Collisions", "M:4/4", "L:\(unitLength)", plan, "K:C", "V:T1", "V:T2",
         "[V:T1] \(upper) |", "[V:T2] \(lower) |"].joined(separator: "\n") + "\n"
    }

    // MARK: - Probes

    private struct ProbedGlyph {
        let character: Character
        let x: Double
        let y: Double
    }

    /// Every Bravura glyph drawn, in document order.
    private func glyphs(in svg: String) -> [ProbedGlyph] {
        svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match in
            guard let x = Double(match.1), let y = Double(match.2),
                  let ch = String(match.3).first else { return nil }
            return ProbedGlyph(character: ch, x: x, y: y)
        }
    }

    private func glyphs(_ kinds: Set<SMuFLGlyph>, in svg: String) -> [ProbedGlyph] {
        let characters = Set(kinds.map(\.character))
        return glyphs(in: svg).filter { characters.contains($0.character) }
    }

    /// Every notehead drawn, left to right and top to bottom within a column.
    private func noteheads(in svg: String) -> [ProbedGlyph] {
        glyphs([.noteheadBlack, .noteheadHalf, .noteheadWhole], in: svg)
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    private func dots(in svg: String) -> [ProbedGlyph] {
        glyphs([.augmentationDot], in: svg).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    private func accidentals(in svg: String) -> [ProbedGlyph] {
        glyphs([.accidentalSharp, .accidentalFlat, .accidentalNatural], in: svg)
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// The width a notehead is displaced by, which is its own.
    private func noteheadWidth() throws -> Double {
        let metadata = try BravuraMetadata.load()
        return try #require(metadata.glyphBBoxes["noteheadBlack"]).width * config.staffSize
    }

    // MARK: - Unison

    @Test("Two voices at the same pitch and duration share one notehead")
    func unisonSharesOneNotehead() throws {
        let document = try svg(tune("c c c c", "c c c c"))
        // Four onsets, one head each: the lower voice draws no second head over the first.
        let heads = noteheads(in: document)
        #expect(heads.count == 4)
        #expect(Set(heads.map(\.y)).count == 1)
    }

    @Test("The voice whose head is not drawn still draws its stem")
    func sharedUnisonKeepsBothStems() throws {
        let metadata = try BravuraMetadata.load()
        let stems = probedStems(in: try svg(tune("c c c c", "c c c c")),
                                staffSize: config.staffSize, metadata: metadata)
        // Two stems per shared head, opposed: what tells a reader two parts are sounding it.
        try #require(stems.count == 8)
        #expect(stems.filter(\.isUp).count == 4)
        #expect(stems.filter { !$0.isUp }.count == 4)
    }

    @Test("A unison the voices cannot share is drawn as two heads, the lower voice's left")
    func unsharableUnisonSeparatesLeftward() throws {
        // Same pitch, different note value: one head cannot say both, so they go side by side.
        // Leftward, so that each stem leaves the pair on its own side rather than running
        // through the other voice's head — `abcm2ps -g` draws this pair the same way.
        let document = try svg(tune("c2 c2", "c c c c"))
        let firstColumn = noteheads(in: document).prefix(2)
        try #require(firstColumn.count == 2)
        let (lower, upper) = (firstColumn[0], firstColumn[1])
        #expect(lower.character == SMuFLGlyph.noteheadBlack.character)
        #expect(upper.character == SMuFLGlyph.noteheadHalf.character)
        #expect(abs((upper.x - lower.x) - (try noteheadWidth())) < 0.01)
    }

    @Test("A unison the voices spell differently separates, and the accidental clears both")
    func unsharableUnisonClearsItsAccidental() throws {
        // `abcm2ps -g` displaces this pair to the *right* and then draws the sharp on top of
        // the displaced notehead.  Separating leftward, as every other unsharable unison
        // does, leaves the accidental somewhere a reader can see it.
        let document = try svg(tune("c4", "^c4"))
        let heads = noteheads(in: document)
        try #require(heads.count == 2)
        #expect(abs((heads[1].x - heads[0].x) - (try noteheadWidth())) < 0.01)
        let sharps = accidentals(in: document)
        try #require(sharps.count == 1)
        #expect(sharps[0].x < heads[0].x)
    }

    // MARK: - Second

    @Test("Two voices a second apart draw offset noteheads, both legible")
    func secondOffsetsTheLowerHead() throws {
        let document = try svg(tune("d d d d", "c c c c"))
        let heads = noteheads(in: document)
        try #require(heads.count == 8)
        // Both heads of every column are drawn, the lower-pitched one a notehead width right:
        // the two stems then nearly coincide, which is what a second between parts looks like
        // in print, and what `abcm2ps -g` draws.
        for column in stride(from: 0, to: 8, by: 2) {
            let (upper, lower) = (heads[column], heads[column + 1])
            #expect(upper.y < lower.y)
            #expect(abs((lower.x - upper.x) - (try noteheadWidth())) < 0.01)
        }
    }

    @Test("A third apart is left alone: the heads clear each other unaided")
    func thirdsAreNotDisplaced() throws {
        let document = try svg(tune("e e e e", "c c c c"))
        let heads = noteheads(in: document)
        try #require(heads.count == 8)
        for column in stride(from: 0, to: 8, by: 2) {
            #expect(heads[column].x == heads[column + 1].x)
        }
    }

    // MARK: - Augmentation dots

    @Test("The dots of a column are drawn in one strip, clear of the rightmost head")
    func dotsShareAStripRightOfBothHeads() throws {
        let document = try svg(tune("c3/2 c/2", "B3/2 B/2"))
        // The first onset is the dotted pair; the eighths after it are the second.
        let firstColumn = noteheads(in: document).prefix(2)
        let dots = dots(in: document)
        try #require(dots.count == 2)
        #expect(dots[0].x == dots[1].x)
        #expect(dots[0].x > firstColumn.map(\.x).max()!)
    }

    @Test("Two dots that would land on one spot are split, the lower one below its note")
    func clashingDotsSplitVertically() throws {
        // `c` sits in a space and keeps its dot beside it; `B` is on the line below, whose dot
        // would be lifted into that same space.  It goes into the space below instead — which
        // is what `abcm2ps -g` draws for this bar.
        let document = try svg(tune("c3/2 c/2", "B3/2 B/2"))
        let firstColumn = noteheads(in: document).prefix(2).sorted { $0.y < $1.y }
        let (c, b) = (firstColumn[0], firstColumn[1])
        let dots = dots(in: document)
        try #require(dots.count == 2)
        #expect(dots[0].y == c.y)
        #expect(dots[1].y == b.y + config.staffSize / 2)
    }

    @Test("A staff of one voice dots its notes exactly as it always has")
    func singleVoiceDotsAreUnmoved() throws {
        let document = try svg("X:1\nT:Alone\nM:4/4\nL:1/4\nK:C\nc3/2 c/2 c3/2 c/2 |\n")
        let heads = noteheads(in: document)
        let dots = dots(in: document)
        try #require(heads.count == 4)
        try #require(dots.count == 2)
        // Notehead, then a fifth of one as a gap: the default the collision pass never touches.
        let gap = try noteheadWidth() * 1.2
        #expect(abs((dots[0].x - heads[0].x) - gap) < 0.01)
        #expect(dots[0].y == heads[0].y)
    }

    // MARK: - Accidentals

    @Test("Accidentals that would overlap are stacked, the lower one further left")
    func accidentalsStackWhenTheyOverlap() throws {
        // A third apart: the heads clear each other, and the accidental glyphs — nearly three
        // staff spaces tall apiece — do not.
        let document = try svg(tune("^e4", "^c4"))
        let heads = noteheads(in: document)
        let sharps = accidentals(in: document)
        try #require(heads.count == 2)
        try #require(sharps.count == 2)
        #expect(heads[0].x == heads[1].x)
        // Sorted by x: the further-left glyph is the lower note's.
        #expect(sharps[0].y > sharps[1].y)
        let metadata = try BravuraMetadata.load()
        let sharpWidth = try #require(metadata.glyphBBoxes["accidentalSharp"]).width * config.staffSize
        #expect(sharps[1].x - sharps[0].x >= sharpWidth)
    }

    @Test("Accidentals a seventh apart clear each other and are left where they were")
    func distantAccidentalsAreNotStacked() throws {
        let document = try svg(tune("^e4", "^F4"))
        let sharps = accidentals(in: document)
        try #require(sharps.count == 2)
        #expect(sharps[0].x == sharps[1].x)
    }

    @Test("A displaced head's accidental hangs off the leftmost head, not its own")
    func accidentalOfADisplacedHeadClearsTheColumn() throws {
        // A second, so the lower voice's head moves right; its sharp stays left of *both*
        // heads rather than following it into the gap between them, where it would be drawn
        // over the upper voice's notehead.
        let document = try svg(tune("e4", "^d4"))
        let heads = noteheads(in: document)
        let sharps = accidentals(in: document)
        try #require(heads.count == 2)
        try #require(sharps.count == 1)
        #expect(sharps[0].x < heads.map(\.x).min()!)
    }

    // MARK: - What must not change

    @Test("A shared staff whose voices never collide is drawn exactly as it was")
    func nonCollidingSharedStaffIsUnchanged() throws {
        // An octave apart, which is where ``SharedStaffVoiceDrawingTests`` keeps its parts:
        // every head stays in the column the sizer put it in.
        let document = try svg(tune("c d e f", "C D E F"))
        let heads = noteheads(in: document)
        try #require(heads.count == 8)
        for column in stride(from: 0, to: 8, by: 2) {
            #expect(heads[column].x == heads[column + 1].x)
        }
    }

    @Test("Two voices on staves of their own collide with nothing")
    func separateStavesAreUntouched() throws {
        // The same unison, planned onto a staff each: two heads, one per staff, and neither
        // of them another voice's to draw.
        let document = try svg(tune("c c c c", "c c c c", plan: "%%score T1 T2"))
        #expect(noteheads(in: document).count == 8)
    }
}
