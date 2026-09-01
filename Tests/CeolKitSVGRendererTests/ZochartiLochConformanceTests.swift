//
//  ZochartiLochConformanceTests.swift
//  CeolKitSVGRendererTests
//
//  §7 Zocharti Loch, engraved.  The parser side of the same source is asserted in
//  `CeolKitParserTests/Conformance/ZochartiLochTests.swift`.
//

import Testing
import SnapshotTesting
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// §7 Zocharti Loch — the standard's own worked example of multi-voice abc, and the hardest
/// shape §11.1 can ask for: `%%score (T1 T2) (B1 B2)`, two voices on each of two staves,
/// with no bracket, no brace and no `|`, so nothing joins the staves but the alignment of
/// what is drawn on them.
///
/// Asserted through `CeolKitSVGGeometry`, which reads the emitted SVG rather than the layout
/// engine's own beliefs, so a system that *thinks* it is aligned and one that is drawn
/// aligned are told apart.
@Suite("§7 Zocharti Loch — rendering")
struct ZochartiLochConformanceTests {

    private let config = SVGRenderConfig()

    /// The weights the emitter drew with, read from the same metadata it read them from.
    private let engravingDefaults = try! BravuraMetadata.load().engravingDefaults

    /// One vertical stroke of the emitted drawing.
    private struct Stroke {
        let x: Double, y1: Double, y2: Double, width: Double?
    }

    private func render() throws -> (svg: String, staves: [SystemGeometry], diagnostics: [Diagnostic]) {
        let result = CeolKitParser().parse(zochartiLochABC, options: .default)
        var diagnostics = result.score.diagnostics
        let pages = try SVGRenderer(config: config).render(result.score, diagnostics: &diagnostics)
        #expect(pages.count == 1)
        let geometry = try SVGGeometry.pages(from: pages)
        return (pages.joined(), geometry.flatMap(\.systems), diagnostics)
    }

    /// The same page drawn as `<text>` rather than outlines, so the glyphs and words on it
    /// can be read back.  Placement is identical either way.
    private func textRender() throws -> (svg: String, staves: [SystemGeometry]) {
        let result = CeolKitParser().parse(zochartiLochABC, options: .default)
        var diagnostics = result.score.diagnostics
        let pages = try textProbeRenderer(config).render(result.score, diagnostics: &diagnostics)
        return (pages.joined(), try SVGGeometry.pages(from: pages).flatMap(\.systems))
    }

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

    /// Every `<text>` run drawn in a given font face, with where it landed.
    private func runs(in svg: String, family: String) -> [(x: Double, y: Double, content: String)] {
        svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="([^"]+)"[^>]*>([^<]*)<\/text>/)
            .compactMap { match in
                guard String(match.3) == family,
                      let x = Double(match.1), let y = Double(match.2) else { return nil }
                return (x: x, y: y, content: String(match.4))
            }
    }

    /// The systems, as lists of the staves drawn on them.  Recovered from the page rather
    /// than assumed: the plan says two staves per system, and that is what is being checked.
    private func systems(_ staves: [SystemGeometry]) -> [[SystemGeometry]] {
        Dictionary(grouping: staves) { $0.left }
            .values
            .map { $0.sorted { $0.topY < $1.topY } }
            .sorted { ($0.first?.topY ?? 0) < ($1.first?.topY ?? 0) }
    }

    // MARK: - Diagnostics

    @Test("§7 renders without a single warning or error")
    func rendersClean() throws {
        let complaints = try render().diagnostics.filter { $0.severity != .info }
        #expect(complaints.isEmpty,
                "Unexpected diagnostics: \(complaints.map { "line \($0.source.line): \($0.message)" })")
    }

    // MARK: - Systems

    @Test("Four voices are drawn on two staves, twice: two systems of two")
    func twoStavesPerSystem() throws {
        let (_, staves, _) = try render()
        // Two source line-sets, each broken nowhere: four staves in all, not eight.  A
        // shared staff that failed to merge would show up here first, as four staves per
        // system rather than two.
        #expect(staves.count == 4)
        #expect(systems(staves).map(\.count) == [2, 2])
    }

    @Test("The staves of a system share one x-span")
    func stavesOfASystemShareAnXSpan() throws {
        let (_, staves, _) = try render()
        for system in systems(staves) {
            #expect(Set(system.map(\.left)).count == 1)
            #expect(Set(system.map(\.right)).count == 1)
        }
    }

    @Test("Bar lines are aligned across both staves of a system")
    func barLinesAlignAcrossTheSystem() throws {
        let (_, staves, _) = try render()
        for (index, system) in systems(staves).enumerated() {
            guard let top = system.first, let bottom = system.last else {
                Issue.record("System \(index) has no staves"); return
            }
            #expect(top.barlineXs.count == 4, "System \(index) has \(top.barlineXs.count) bars")
            #expect(bottom.barlineXs.count == top.barlineXs.count)
            for (x, expected) in zip(bottom.barlineXs, top.barlineXs) {
                #expect(abs(x - expected) < 0.5,
                        "System \(index): bar line at \(x) against \(expected)")
            }
        }
    }

    @Test("The abcLine anchors run down the page")
    func abcLineAnchorsAreMonotonic() throws {
        let result = CeolKitParser().parse(zochartiLochABC, options: .default)
        var diagnostics: [Diagnostic] = []
        let pages = try SVGRenderer(config: config).render(result.score, diagnostics: &diagnostics)
        for page in try SVGGeometry.pages(from: pages) {
            let lines = page.systems.compactMap(\.abcLine)
            #expect(lines.count == page.systems.count, "Some system carries no anchor")
            #expect(lines == lines.sorted(), "Anchors out of order: \(lines)")
        }
    }

    // MARK: - What the plan does *not* ask for

    @Test("No bracket and no brace: the plan uses ( ) alone")
    func noStaffFurniture() throws {
        let (svg, staves, _) = try render()
        // A bracket's spine is the one stroke that both opens flush with a staff's top line
        // and stands left of that staff — the test `StaffBracketTests` and the Canzonetta
        // fixture identify it by.  Here there should be none, and no brace glyph either.
        let spines = verticalStrokes(in: svg).filter { stroke in
            staves.contains { abs($0.topY - stroke.y1) < 1e-3 && stroke.x < $0.left - 1e-9 }
        }
        #expect(spines.isEmpty, "Something is drawn left of a staff: \(spines.map(\.x))")

        let braces = runs(in: try textRender().svg, family: "Bravura")
            .filter { $0.content.contains(SMuFLGlyph.brace.character) }
        #expect(braces.isEmpty)
    }

    @Test("Bar lines stop at their own staff — no `|` in the plan, no continued bar lines")
    func barLinesAreNotContinued() throws {
        let (svg, staves, _) = try render()
        let strokes = verticalStrokes(in: svg)
        for (index, system) in systems(staves).enumerated() {
            guard let top = system.first else { Issue.record("System \(index) is empty"); return }
            let staffLineWidth = engravingDefaults.staffLineThickness * top.staffLineGap
            let tolerance = top.staffLineGap * 0.1
            for x in top.barlineXs {
                let overrun = strokes
                    .filter { abs($0.x - x) < tolerance && abs($0.y1 - top.topY) < tolerance }
                    .filter { ($0.width ?? .infinity) > staffLineWidth }
                    .map { $0.y2 - top.bottomY }
                    .max()
                guard let overrun else { Issue.record("No bar line at \(x)"); return }
                #expect(overrun < tolerance,
                        "System \(index): the bar line at \(x) runs \(overrun) past its staff")
            }
        }
    }

    // MARK: - Voice names (§4.1)

    @Test("Each staff is named for the voice written at the top of it")
    func staffNames() throws {
        let (svg, staves) = try textRender()
        let words = runs(in: svg, family: "Libertinus Serif")
        // `name=` on the first system, `snm=` on the second (§4.1).  A shared staff takes
        // both from the voice written first in it — see CONFORMANCE.md — so "Tenore II"
        // and "Basso II" are nowhere on the page.
        for (staff, expected) in zip(systems(staves).flatMap { $0 },
                                     ["Tenore I", "Basso I", "T.I", "B.I"]) {
            // The gutter's own baseline, so the tempo mark standing above the first staff
            // — which is also set left of the music — is not mistaken for a voice name.
            let baselineY = staff.topY + VoiceLabelGutter.baselineOffset(staffSize: staff.staffLineGap)
            let onThisStaff = words.filter {
                $0.x < staff.left && abs($0.y - baselineY) < 1e-6
            }
            #expect(onThisStaff.map(\.content) == [expected])
        }
        #expect(!words.contains { $0.content.contains("Tenore II") })
        #expect(!words.contains { $0.content.contains("Basso II") })
    }

    // MARK: - Octave clefs (§4.6)

    @Test("clef=treble-8 is drawn with its 8, and clef=bass without one")
    func octaveClefs() throws {
        let (svg, staves) = try textRender()
        let clefs = runs(in: svg, family: "Bravura").filter {
            $0.content.contains(SMuFLGlyph.gClef8vb.character)
                || $0.content.contains(SMuFLGlyph.gClef.character)
                || $0.content.contains(SMuFLGlyph.fClef.character)
        }
        // One clef per staff: the tenors' octave-down G clef, the basses' plain F clef.
        #expect(clefs.filter { $0.content.contains(SMuFLGlyph.gClef8vb.character) }.count == 2)
        #expect(clefs.filter { $0.content.contains(SMuFLGlyph.gClef.character) }.isEmpty,
                "A plain G clef was drawn for a `treble-8` voice")
        #expect(clefs.filter { $0.content.contains(SMuFLGlyph.fClef.character) }.count == 2)

        // The wider glyph is paid for out of the header, not out of the music: whatever the
        // clef costs, the staff still starts where the system's other staff starts.
        for system in systems(staves) {
            #expect(Set(system.map(\.left)).count == 1)
        }
    }

    // MARK: - Invisible rests (§4.9)

    @Test("B2's x8 bars draw nothing, while B1's z8 draws a whole rest")
    func invisibleRestsAreNotDrawn() throws {
        let (svg, staves) = try textRender()
        guard let bassStaff = systems(staves).first?.last else {
            Issue.record("Nothing was drawn"); return
        }
        // The opening system's bass staff carries B1's `z8 | z2f2 g2a2 | b2z2 z2 e2 | f4 f2z2`
        // and B2's four bars of `x8`.  Every rest drawn there is therefore B1's: five in
        // all — the opening whole bar, then one each in bars 2, 3 (two of them) and 4.
        let restGlyphs: Set<Character> = [
            SMuFLGlyph.restWhole.character, SMuFLGlyph.restHalf.character,
            SMuFLGlyph.restQuarter.character, SMuFLGlyph.rest8th.character,
        ]
        let rests = runs(in: svg, family: "Bravura").filter { run in
            run.content.contains { restGlyphs.contains($0) }
                && abs(run.y - bassStaff.topY) < 6 * bassStaff.staffLineGap
                && run.y > bassStaff.topY - 2 * bassStaff.staffLineGap
        }
        #expect(rests.count == 5, "Drew \(rests.map(\.content).count) rests on the bass staff")
        // The first is the whole-bar rest that stands alone in bar 1 — B2's `x8` beside it
        // is not drawn, and does not push it off centre either (see `SVGEmitter.inkedVoices`).
        guard let first = rests.min(by: { $0.x < $1.x }) else { return }
        #expect(first.content.contains(SMuFLGlyph.restWhole.character))
        #expect(abs(first.y - (bassStaff.topY + bassStaff.staffLineGap)) < 1e-6,
                "The lone whole rest is not hanging from the fourth line")
    }

    // MARK: - Snapshot

    // The snapshot file's basename has to be unique across the whole test target:
    // `__Snapshots__` is declared `.process(…)` in `Package.swift`, which flattens it, and
    // `CanzonettaConformanceTests` already has a `pageMatchesSnapshot`.
    @Test("The engraved page does not drift")
    func zochartiPageMatchesSnapshot() throws {
        // Outline data replaced for the reason `IntegrationTests` gives: this snapshot is
        // about structure and placement, and a few thousand curve coordinates would bury
        // it.  The outlines are checked against Bravura's own boxes in `OpenTypeFontTests`.
        let sanitized = try render().svg.replacing(
            /(<path id="[^"]+" d=")[^"]+"/,
            with: { "\($0.output.1)<OUTLINE>\"" }
        )
        assertSnapshot(of: sanitized, as: .lines)
    }
}

/// §7 of the ABC v2.2 standard, verbatim.
private let zochartiLochABC = """
X:1
T:Zocharti Loch
C:Louis Lewandowski (1821-1894)
M:C
Q:1/4=76
%%score (T1 T2) (B1 B2)
V:T1  clef=treble-8  name="Tenore I"   snm="T.I"
V:T2  clef=treble-8  name="Tenore II"  snm="T.II"
V:B1  clef=bass      name="Basso I"    snm="B.I"  octave=-2
V:B2  clef=bass      name="Basso II"   snm="B.II" octave=-2
K:Gm
%            End of header, start of tune body:
% 1
[V:T1]  (B2c2 d2g2)  | f6e2      | (d2c2 d2)e2 | d4 c2z2 |
[V:T2]  (G2A2 B2e2)  | d6c2      | (B2A2 B2)c2 | B4 A2z2 |
[V:B1]       z8      | z2f2 g2a2 | b2z2 z2 e2  | f4 f2z2 |
[V:B2]       x8      |     x8    |      x8     |    x8   |
% 5
[V:T1]  (B2c2 d2g2)  | f8        | d3c (d2fe)  | H d6    ||
[V:T2]       z8      |     z8    | B3A (B2c2)  | H A6    ||
[V:B1]  (d2f2 b2e'2) | d'8       | g3g  g4     | H^f6    ||
[V:B2]       x8      | z2B2 c2d2 | e3e (d2c2)  | H d6    ||
"""
