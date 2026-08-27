import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #73: staves joined by a brace or bracket sit closer together than staves that are
/// merely adjacent in the same system, so `[{A B} C]` reads as "A and B belong together, C
/// is alongside" from the spacing alone rather than only from the furniture.
///
/// The gaps are measured off the drawing rather than off the layout engine, because the
/// spacing is only worth anything as ink on the page: what is asserted is the distance from
/// one staff's bottom line to the next staff's top line, which is what a reader sees.
@Suite("Staff Spacing")
struct StaffSpacingTests {

    private let config = SVGRenderConfig()
    private let metadata = try! BravuraMetadata.load()

    // MARK: - Rendering

    private func render(_ abc: String, config: SVGRenderConfig? = nil)
    -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: config ?? self.config).render(score,
                                                                         diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    /// `n` voices, one line each, with `directive` above the `K:`.
    ///
    /// Every note sits between the staff lines, so no staff reserves room for ledger lines
    /// and the space between two staves is exactly the gap the engine put there.
    private func voices(_ count: Int, _ directive: String? = nil) -> String {
        let heads = (1...count).map { "V:\($0)" }
        let bodies = (1...count).map { "[V:\($0)] EFGA Bcde | fedc BAGF |" }
        let header = ["X:1", "T:Spacing", "M:4/4", "L:1/8"] + (directive.map { [$0] } ?? []) + ["K:C"]
        return (header + heads + bodies).joined(separator: "\n")
    }

    /// The vertical space between staff `i` and staff `i + 1`: bottom line to top line.
    private func gaps(_ staves: [SystemGeometry]) -> [Double] {
        zip(staves, staves.dropFirst()).map { $1.topY - $0.bottomY }
    }

    // MARK: - Grouped spacing

    @Test("Within a span the staves sit closer than adjacent staves, which sit closer than systems")
    func withinSpanIsTighterThanBetweenSpansIsTighterThanSystems() {
        #expect(config.spanStaffGap < config.staffGap)
        #expect(config.staffGap < config.systemGap)
    }

    @Test("`[{A B} C]`: the braced pair is tightened, the staff alongside it is not")
    func spannedBoundaryTightensAndTheOtherDoesNot() {
        let staves = render(voices(3, "%%score [{1 2} 3]")).staves
        let measured = gaps(staves)
        #expect(measured.count == 2)
        #expect(abs(measured[0] - config.spanStaffGap) < 1e-6)
        #expect(abs(measured[1] - config.staffGap) < 1e-6)
    }

    @Test("A bracket tightens what it covers exactly as a brace does")
    func bracketTightensToo() {
        let staves = render(voices(3, "%%score [1 2] 3")).staves
        let measured = gaps(staves)
        #expect(abs(measured[0] - config.spanStaffGap) < 1e-6)
        #expect(abs(measured[1] - config.staffGap) < 1e-6)
    }

    @Test("A plan grouping every staff tightens every boundary")
    func oneSpanOverAllStavesTightensAllOfThem() {
        let measured = gaps(render(voices(3, "%%score {1 2 3}")).staves)
        #expect(measured.allSatisfy { abs($0 - config.spanStaffGap) < 1e-6 })
    }

    @Test("Two braced pairs under one bracket are tight inside and apart from each other")
    func siblingSpansAreSeparatedFromEachOther() {
        let measured = gaps(render(voices(4, "%%score [{1 2} {3 4}]")).staves)
        #expect(measured.count == 3)
        #expect(abs(measured[0] - config.spanStaffGap) < 1e-6)
        // The boundary between the two pairs meets only at the bracket outside them both.
        #expect(abs(measured[1] - config.staffGap) < 1e-6)
        #expect(abs(measured[2] - config.spanStaffGap) < 1e-6)
    }

    // MARK: - The ungrouped page is unchanged

    @Test("A multi-voice tune with no plan is spaced exactly as it was before spans existed")
    func ungroupedMultiVoiceIsUnchanged() {
        let measured = gaps(render(voices(3)).staves)
        #expect(measured.count == 2)
        #expect(measured.allSatisfy { abs($0 - config.staffGap) < 1e-6 })
    }

    @Test("A plan that only orders the voices groups nothing, and tightens nothing")
    func aPlanWithNoSpansTightensNothing() {
        let measured = gaps(render(voices(3, "%%score 1 2 3")).staves)
        #expect(measured.allSatisfy { abs($0 - config.staffGap) < 1e-6 })
    }

    // MARK: - Scale

    @Test("Halving the tune halves the gaps, and the furniture with them")
    func scalingTakesTheGapsAndTheFurnitureTogether() throws {
        let (svg, staves) = render(voices(2, "%%score {1 2}\n%%ceolkit:scale 0.5"),
                                   config: {
                                       var pinned = config
                                       pinned.textRendering = .fontFace
                                       return pinned
                                   }())
        // The music is half size…
        #expect(abs(staves[0].staffLineGap - config.staffSize / 2) < 1e-6)
        // …and so is the space between the braced staves.
        #expect(abs(gaps(staves)[0] - config.spanStaffGap / 2) < 1e-6)

        // The brace still reaches from the first staff's top line to the last's bottom one,
        // which is the whole of what the tightened gap changed.
        let brace = try #require(braces(in: svg).first)
        let natural = try #require(metadata.glyphBBoxes["brace"])
        #expect(abs(brace.y - staves[1].bottomY) < 1e-3)
        #expect(abs(brace.y - natural.height * staves[0].staffLineGap * brace.yScale
                    - staves[0].topY) < 1e-3)
    }

    // MARK: - Furniture over an uneven group

    @Test("A brace over a staff with ledger lines below still lands on its bottom staff line")
    func braceTerminatesOnTheStaffLinesNotShortOfThem() throws {
        var pinned = config
        pinned.textRendering = .fontFace
        // The lower staff runs an octave and a half below the staff, so its band is much
        // taller than the staff it draws.  The brace's foot belongs on the staff line all
        // the same — the span is measured from the staves, not from the bands.
        let abc = """
            X:1
            T:Deep
            M:4/4
            L:1/8
            %%score {1 2}
            K:C
            V:1
            V:2
            [V:1] EFGA Bcde | fedc BAGF |
            [V:2] C,D,E,F, G,A,B,C | C,D,E,F, G,A,B,C |
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try SVGRenderer(config: pinned).render(score, diagnostics: &diagnostics)
        let staves = try SVGGeometry.pages(from: svgs).flatMap(\.systems)
        let brace = try #require(braces(in: svgs.joined()).first)
        let natural = try #require(metadata.glyphBBoxes["brace"])

        #expect(abs(brace.y - staves[1].bottomY) < 1e-3)
        #expect(abs(brace.y - natural.height * config.staffSize * brace.yScale
                    - staves[0].topY) < 1e-3)
        // …and the ledger lines really are down there, below the foot it stopped at, so the
        // test is measuring the case it says it is.
        #expect(lowestInk(in: svgs.joined()) > staves[1].bottomY + config.staffSize)
        // The group's own spacing is untouched by an extent that grows below it.
        #expect(abs(gaps(staves)[0] - config.spanStaffGap) < 1e-6)
    }

    // MARK: - Which boundaries count as joined

    @Test("Only a span that is actually drawn tightens the staves it covers")
    func anUndrawnSpanTightensNothing() {
        let brace = StaffGrouping.Span(bracket: .brace, staves: 0...1, depth: 0)
        let joined = BracketColumns(grouping: StaffGrouping(spans: [brace], barlineJoins: []),
                                    staffCount: 3, metadata: metadata, staffSize: 6)
        #expect(joined.sharesInnermostSpan(0, 1))
        #expect(!joined.sharesInnermostSpan(1, 2))

        // A span reaching past the staves the system actually has is dropped rather than
        // clamped, so it groups nothing — and must tighten nothing either, or the page
        // would show a closer pair with no mark saying why.
        let overreaching = StaffGrouping.Span(bracket: .brace, staves: 0...3, depth: 0)
        let dropped = BracketColumns(grouping: StaffGrouping(spans: [overreaching],
                                                            barlineJoins: []),
                                     staffCount: 3, metadata: metadata, staffSize: 6)
        #expect(!dropped.sharesInnermostSpan(0, 1))

        // A span over a single staff has no furniture and no boundary of its own.
        let single = StaffGrouping.Span(bracket: .bracket, staves: 1...1, depth: 0)
        let alone = BracketColumns(grouping: StaffGrouping(spans: [single], barlineJoins: []),
                                   staffCount: 3, metadata: metadata, staffSize: 6)
        #expect(!alone.sharesInnermostSpan(0, 1))
        #expect(!alone.sharesInnermostSpan(1, 2))
    }

    // MARK: - Helpers

    /// The brace as it reaches the page in `.fontFace`: a group carrying the placement and
    /// the two stretch factors, around a `<text>` drawn at the origin.
    private struct DrawnBrace {
        let x: Double, y: Double, xScale: Double, yScale: Double
    }

    /// The lowest y any horizontal rule reaches in the drawing — with these tunes, the
    /// bottom ledger line of the deepest note.
    private func lowestInk(in svg: String) -> Double {
        svg.matches(of: /<line x1="[-0-9.]+" y1="([-0-9.]+)" x2="[-0-9.]+" y2="([-0-9.]+)"/)
            .compactMap { match in
                guard let y1 = Double(match.1), let y2 = Double(match.2),
                      abs(y1 - y2) < 1e-9 else { return nil }
                return y1
            }
            .max() ?? 0
    }

    private func braces(in svg: String) -> [DrawnBrace] {
        let brace = String(SMuFLGlyph.brace.character)
        return svg.matches(of: /<g transform="translate\(([-0-9.]+) ([-0-9.]+)\) scale\(([-0-9.]+) ([-0-9.]+)\)">\s*<text [^>]*>(.)<\/text>/)
            .compactMap { match in
                guard String(match.5) == brace,
                      let x = Double(match.1), let y = Double(match.2),
                      let sx = Double(match.3), let sy = Double(match.4) else { return nil }
                return DrawnBrace(x: x, y: y, xScale: sx, yScale: sy)
            }
    }
}
