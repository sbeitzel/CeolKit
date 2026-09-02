import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #68: a bar line runs on into the staff below only where the plan joins the two
/// with `|` (ABC v2.2 §11.1).  Without a plan every boundary is joined, which is how
/// multi-voice systems have been drawn since #58.
///
/// End to end — source in, SVG out — because the whole point of the change is the length
/// of a stroke on the page.
@Suite("Continued Bar Lines")
struct ContinuedBarlineTests {

    /// The weights the emitter drew with, read from the same metadata it read them from.
    private let engravingDefaults = try! BravuraMetadata.load().engravingDefaults

    /// One vertical stroke of the emitted drawing.
    private struct Stroke {
        let x: Double, y1: Double, y2: Double, width: Double?
    }

    private func render(_ abc: String) -> (svg: String, staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer().render(score, diagnostics: &diagnostics)
        let pages = try! SVGGeometry.pages(from: svgs)
        return (svgs.joined(), pages.flatMap(\.systems))
    }

    /// The drawing's vertical strokes.  Read straight out of the SVG rather than through
    /// `CeolKitSVGGeometry`, which reports where a bar line is and not how far it reaches.
    private func verticalStrokes(in svg: String) -> [Stroke] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"(?: stroke="[^"]*")?(?: stroke-width="([-0-9.]+)")?/)
            .compactMap { match in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      abs(x1 - x2) < 1e-9 else { return nil }
                return Stroke(x: x1, y1: min(y1, y2), y2: max(y1, y2),
                              width: match.5.flatMap { Double($0) })
            }
    }

    /// How far below its own bottom staff line the bar line at `x` on `staff` reaches.
    ///
    /// Picked out by the same stroke-width test `CeolKitSVGGeometry` uses: a bar line is
    /// drawn thicker than the staff lines, a stem thinner, and the rule joining the staves
    /// at the left edge is drawn at the staff lines' own weight.
    ///
    /// `staffLineGap` is the staff size the system was actually drawn at, so this tracks
    /// `%%ceolkit:scale` exactly as the strokes being separated do.
    private func barlineOverrun(at x: Double, on staff: SystemGeometry,
                                strokes: [Stroke]) -> Double? {
        let tolerance = staff.staffLineGap * 0.1
        let bottomY = staff.topY + 4 * staff.staffLineGap
        let staffLineWidth = engravingDefaults.staffLineThickness * staff.staffLineGap
        return strokes
            .filter { abs($0.x - x) < tolerance && abs($0.y1 - staff.topY) < tolerance }
            .filter { ($0.width ?? .infinity) > staffLineWidth }
            .map { $0.y2 - bottomY }
            .max()
    }

    /// Two voices, one line of two bars each, with `directive` above the `K:`.
    private func twoVoices(_ directive: String = "") -> String {
        ([
            "X:1", "T:Two Voices", "M:4/4", "L:1/8", directive, "K:D", "V:1", "V:2",
            "[V:1] abcd efga | bage dcBA |",
            "[V:2] ABcd efga | bage dcBA |",
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The overrun of every bar line on the system's top staff, and the gap to the staff
    /// below it — what a continued bar line has to cross to reach the next staff.
    private func topStaffOverruns(_ abc: String) -> (overruns: [Double], gap: Double) {
        let (svg, staves) = render(abc)
        let strokes = verticalStrokes(in: svg)
        precondition(staves.count == 2, "expected one system of two staves")
        let top = staves[0]
        let overruns = top.barlineXs.compactMap { barlineOverrun(at: $0, on: top, strokes: strokes) }
        let gap = staves[1].topY - (top.topY + 4 * top.staffLineGap)
        return (overruns, gap)
    }

    @Test("%%score [1|2] continues the bar lines into the staff below")
    func joinedBoundaryContinues() {
        let (overruns, gap) = topStaffOverruns(twoVoices("%%score [1|2]"))
        #expect(!overruns.isEmpty)
        #expect(overruns.allSatisfy { abs($0 - gap) < 1e-9 })
    }

    @Test("%%score [1 2] stops each bar line at its own staff")
    func unjoinedBoundaryStops() {
        let (overruns, gap) = topStaffOverruns(twoVoices("%%score [1 2]"))
        #expect(!overruns.isEmpty)
        #expect(gap > 0)
        #expect(overruns.allSatisfy { abs($0) < 1e-9 })
    }

    @Test("%%staves [1 2] is the inversion, and continues them")
    func stavesDirectiveIsInverted() {
        let (overruns, gap) = topStaffOverruns(twoVoices("%%staves [1 2]"))
        #expect(!overruns.isEmpty)
        #expect(overruns.allSatisfy { abs($0 - gap) < 1e-9 })
    }

    @Test("With no directive the bar lines continue, exactly as they did before")
    func noDirectiveIsUnchanged() {
        let (overruns, gap) = topStaffOverruns(twoVoices())
        #expect(!overruns.isEmpty)
        #expect(overruns.allSatisfy { abs($0 - gap) < 1e-9 })
    }

    /// The gate changes how far a bar line reaches, not whether it was drawn — the whole
    /// page other than that is the same drawing.
    @Test("Only the bar lines' length differs between joined and unjoined")
    func nothingElseChanges() {
        let joined = render(twoVoices("%%score [1|2]")).svg
        let unjoined = render(twoVoices("%%score [1 2]")).svg
        #expect(joined != unjoined)
        #expect(verticalStrokes(in: joined).count == verticalStrokes(in: unjoined).count)
        // The left-edge rule still runs the full height of the group in both, so the
        // bracket the plan asks for still reads as spanning both staves.
        let extent = { (svg: String) -> Double? in
            self.verticalStrokes(in: svg).map { $0.y2 - $0.y1 }.max()
        }
        #expect(extent(joined) == extent(unjoined))
    }

    /// `CeolKitSVGGeometry` infers bar lines from stroke geometry, so it has to keep
    /// finding them when they no longer outrun their staff.
    @Test("Geometry recovers the same bar lines in both modes")
    func geometryIsUnaffected() {
        let joined = render(twoVoices("%%score [1|2]")).staves
        let unjoined = render(twoVoices("%%score [1 2]")).staves
        #expect(joined.map(\.barlineXs) == unjoined.map(\.barlineXs))
        #expect(joined[0].barlineXs.count == 2)
    }
}
