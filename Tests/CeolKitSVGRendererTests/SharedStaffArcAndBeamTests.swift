import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #78: the emitter's per-measure accumulators — the open beam run, the open ties, the
/// open slurs — belong to a *part*, not to a staff.
///
/// A `%%score ( … )` staff (§11.1) interleaves its voices in one event stream, so a single
/// accumulator takes one voice's beam start as the end of the other's run, closes one voice's
/// tie with the other's equal pitch, and — a slur carrying neither pitch nor any other mark to
/// match on — pairs interleaved slurs by nothing better than arrival order.  The same array of
/// open anchors is threaded across every staff of every system (#27), which lets a staff
/// resolve or re-dangle an arc opened on the staff above it, drawn at that staff's y.
///
/// End to end, source in and SVG out, like ``SharedStaffVoiceDrawingTests``: every one of these
/// is a question about what got *drawn*, and the layout it was drawn from was already right.
@Suite("Shared staff: beams, ties and slurs bucketed by voice")
struct SharedStaffArcAndBeamTests {

    private let config = SVGRenderConfig()

    private func svg(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
    }

    /// A two-voice tune, both voices on one staff unless `plan` says otherwise.
    private func tune(_ upper: String, _ lower: String, unitLength: String = "1/4",
                      plan: String = "%%score (T1 T2)") -> String {
        (["X:1", "T:Shared", "M:4/4", "L:\(unitLength)", plan, "K:C", "V:T1", "V:T2"]
            + zip(upper.split(separator: "|"), lower.split(separator: "|")).flatMap {
                ["[V:T1] \($0.0.trimmingCharacters(in: .whitespaces)) |",
                 "[V:T2] \($0.1.trimmingCharacters(in: .whitespaces)) |"]
            }).joined(separator: "\n") + "\n"
    }

    // MARK: - Probes

    /// Every horizontal `<line>` in the document, as its y, its ends, and its weight.
    private func horizontals(in svg: String) -> [(y: Double, x1: Double, x2: Double, width: Double)] {
        svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { match in
            guard let x1 = Double(match.1), let y1 = Double(match.2), let x2 = Double(match.3),
                  let y2 = Double(match.4), let w = Double(match.5), y1 == y2 else { return nil }
            return (y1, x1, x2, w)
        }
    }

    /// The y of every staff line drawn, top to bottom — five per staff.
    ///
    /// Staff lines are the horizontals that run a whole system's width; nothing else drawn
    /// here (beams, ledger lines) comes close to that length.
    private func staffLineYs(in svg: String) throws -> [Double] {
        let hs = horizontals(in: svg)
        let systemWidth = try #require(hs.map { $0.x2 - $0.x1 }.max())
        return hs.filter { $0.x2 - $0.x1 == systemWidth }.map(\.y).sorted()
    }

    /// Every beam stroke: the horizontals at Bravura's beam thickness, which is thicker than
    /// any staff or ledger line in the document.
    private func beams(in svg: String, metadata: BravuraMetadata) -> [(x1: Double, x2: Double, y: Double)] {
        let thickness = metadata.engravingDefaults.beamThickness * config.staffSize
        return horizontals(in: svg)
            .filter { abs($0.width - thickness) < 0.01 }
            .map { (x1: $0.x1, x2: $0.x2, y: $0.y) }
            .sorted { $0.y < $1.y }
    }

    /// One drawn tie or slur, reduced to the two ends of its centre line.
    private struct ProbedArc {
        let startX: Double
        let endX: Double
        /// Y of the endpoints — the notehead's y shifted a staff space clear of it, so it says
        /// which part drew the arc without being that part's notehead y.
        let y: Double
    }

    /// Every arc painted on the page.
    ///
    /// A drawn arc is the only `<path d=…>` in a document rendered this way: glyph outlines
    /// live in `<defs>` as `<path id=…>`, and this renderer draws its glyphs as `<text>`
    /// anyway.  The `d` is `M … C … L … C … Z` — one boundary of the tapered ribbon out and
    /// the other back — so its 16 coordinates hold each endpoint twice, half the ribbon's end
    /// thickness either side of the centre line.
    private func arcs(in svg: String) -> [ProbedArc] {
        svg.components(separatedBy: "<path d=\"").dropFirst()
            .compactMap { $0.components(separatedBy: "\"").first }
            .compactMap { d in
                let c = d.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
                guard c.count == 16 else { return nil }
                return ProbedArc(startX: c[0], endX: c[6], y: (c[1] + c[15]) / 2)
            }
    }

    /// The x of every onset in the bar, left to right: one per column of the merged grid.
    ///
    /// Both voices of a shared staff draw at the x of the onset they share (#76), so the
    /// distinct notehead x's *are* the columns, and an arc's endpoints can be named by which
    /// column they land on rather than by a coordinate.
    private func onsetXs(in svg: String) -> [Double] {
        let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                     SMuFLGlyph.noteheadHalf.character,
                                     SMuFLGlyph.noteheadWhole.character]
        let xs = svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match -> Double? in
            guard let x = Double(match.1), let ch = String(match.3).first,
                  heads.contains(ch) else { return nil }
            return x
        }
        return Array(Set(xs)).sorted()
    }

    // MARK: - Beams

    @Test("Each voice of a shared staff is beamed on its own, not with its neighbour")
    func eachVoiceKeepsItsOwnBeamRun() throws {
        // Four beamed eighths in each voice, note for note.  Interleaved into one stream the
        // lower voice's `.start` arrives inside the upper voice's open run, and a single
        // accumulator answers it by flushing that run and beaming the rest of both voices
        // together — one beam where there should be two.
        let metadata = try BravuraMetadata.load()
        let document = try svg(tune("cdef c4", "CDEF C4", unitLength: "1/8"))
        let drawn = beams(in: document, metadata: metadata)
        try #require(drawn.count == 2, "expected one beam per voice, got \(drawn.count)")
        // The upper voice stems up and the lower down (#77), so the staff is between them.
        let staff = try staffLineYs(in: document)
        try #require(staff.count == 5)
        #expect(drawn[0].y < staff.first!)
        #expect(drawn[1].y > staff.last!)
    }

    @Test("Beam runs of different lengths keep their own extents")
    func beamRunsOfDifferentLengthsDoNotMerge() throws {
        // Six beamed eighths above, four below, starting two columns later: the two runs
        // overlap without coinciding, so a merged group could not pass for either of them.
        let metadata = try BravuraMetadata.load()
        let document = try svg(tune("cdefga c2", "C2 DEFG C2", unitLength: "1/8"))
        let drawn = beams(in: document, metadata: metadata)
        try #require(drawn.count == 2)
        let (upper, lower) = (drawn[0], drawn[1])
        #expect(upper.x1 < lower.x1)
        #expect(upper.x2 > lower.x2)
    }

    // MARK: - Ties

    @Test("A tie is closed by its own voice, not by an equal pitch in the other")
    func tieIsNotClosedByTheOtherVoice() throws {
        // Both voices tie the same pitch, the lower voice's tie opening and closing inside the
        // upper voice's.  Matching on pitch alone hands the upper voice's anchor to the first
        // note that asks for one, which is the lower voice's — and the two arcs come out
        // crossed, each spanning from one voice's note to the other's.
        let document = try svg(tune("c3- c", "z c- c z"))
        let drawn = arcs(in: document).sorted { $0.startX < $1.startX }
        try #require(drawn.count == 2)
        let columns = onsetXs(in: document)
        try #require(columns.count == 4)
        // Outer arc: the upper voice's, column 0 to column 3.  Inner: the lower voice's, 1 to 2.
        #expect(drawn[0].endX == columns[3])
        #expect(drawn[1].endX == columns[2])
        #expect(drawn[0].startX > columns[0] && drawn[0].startX < columns[1])
        #expect(drawn[1].startX > columns[1] && drawn[1].startX < columns[2])
    }

    // MARK: - Slurs

    @Test("Interleaved slurs resolve to the voice that opened them")
    func interleavedSlursPairWithinTheirVoice() throws {
        // The upper voice's slur opens first and closes first; the lower voice's opens inside
        // it and closes after it.  A single LIFO stack answers the upper voice's `)` with the
        // lower voice's anchor, which pairs each arc with the other part's note.
        let document = try svg(tune("(c d e) f", "C (D E F)"))
        let drawn = arcs(in: document).sorted { $0.y < $1.y }
        try #require(drawn.count == 2)
        let columns = onsetXs(in: document)
        try #require(columns.count == 4)
        let (upper, lower) = (drawn[0], drawn[1])
        #expect(upper.endX == columns[2])
        #expect(lower.endX == columns[3])
        #expect(upper.startX < lower.startX)
    }

    // MARK: - Across a break

    @Test("A tie spanning a system break dangles once per voice, on its own part")
    func tiesDangleAcrossASystemBreakPerVoice() throws {
        // Both voices tie across the break, so each should leave a departing arc at the first
        // system's right edge and pick up an arriving one at the second system's left edge:
        // four arcs, at four different heights, two per system.
        let document = try svg(tune("c4- | c4", "C4- | C4"))
        let drawn = arcs(in: document).sorted { $0.y < $1.y }
        try #require(drawn.count == 4)
        #expect(Set(drawn.map(\.y)).count == 4)

        let (departing, arriving) = (Array(drawn.prefix(2)), Array(drawn.suffix(2)))
        let rightEdge = try #require(drawn.map(\.endX).max())
        let leftEdge  = try #require(drawn.map(\.startX).min())
        #expect(departing.allSatisfy { $0.endX == rightEdge })
        #expect(arriving.allSatisfy { $0.startX == leftEdge })
    }

    @Test("An unclosed tie does not follow its pitch onto the staff below")
    func anOpenTieStaysOnItsOwnStaff() throws {
        // Two staves this time, not a shared one.  The upper voice opens a tie it never closes
        // and the lower voice sounds the same pitch: the anchors are threaded across both
        // staves, so an undiscriminated match lets the lower staff resolve it — and draw the
        // arc at the upper staff's y, a staff clear of any note in it.
        let document = try svg(tune("c- d e f", "c d e f", plan: "%%score T1 T2"))
        let drawn = arcs(in: document)
        try #require(drawn.count == 1, "expected one dangling arc, got \(drawn.count)")
        let staff = try staffLineYs(in: document)
        try #require(staff.count == 10)
        // Inside the upper staff, where the note it dangles from is — not near the lower one.
        #expect(drawn[0].y > staff[0] && drawn[0].y < staff[4])
    }
}
