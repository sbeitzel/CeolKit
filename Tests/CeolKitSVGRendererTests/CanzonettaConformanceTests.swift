//
//  CanzonettaConformanceTests.swift
//  CeolKitSVGRendererTests
//
//  §14.4 Canzonetta.abc, rendered.  The parser side of the same source is asserted in
//  `CeolKitParserTests/Conformance/CanzonettaTests.swift`; this is the engraved shape.
//

import Testing
import SnapshotTesting
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// §14.4 Canzonetta.abc — the first spec example that reaches the renderer whole:
/// `%%score [1 2 3]`, three named voices, one bracket, no shared staves.
///
/// Asserted through `CeolKitSVGGeometry`, which reads the emitted SVG rather than the
/// layout engine's own beliefs, so a system that *thinks* it is aligned and one that is
/// drawn aligned are told apart.
///
/// The tune carries two `w:` verses per stave, one of them continued across a `\\` line
/// break, so it is also the fixture that says whether lyrics are engraved (issue #82).
@Suite("§14.4 Canzonetta.abc — rendering")
struct CanzonettaConformanceTests {

    private let config = SVGRenderConfig()

    /// One vertical stroke of the emitted drawing.  Read straight out of the SVG, because
    /// `CeolKitSVGGeometry` reports staves and bar lines and a bracket is deliberately
    /// neither — the same reading `StaffBracketTests` does.
    private struct Stroke {
        let x: Double, y1: Double, y2: Double
    }

    private func render() throws -> (svg: String, staves: [SystemGeometry], diagnostics: [Diagnostic]) {
        let result = CeolKitParser().parse(canzonettaABC, options: .default)
        var diagnostics = result.score.diagnostics
        let pages = try SVGRenderer(config: config).render(result.score, diagnostics: &diagnostics)
        // One page: the whole point of the fixture is that the three systems land together.
        #expect(pages.count == 1)
        let geometry = try SVGGeometry.pages(from: pages)
        return (pages.joined(), geometry.flatMap(\.systems), diagnostics)
    }

    /// The brackets: the vertical strokes that open flush with some staff's top line and
    /// stand left of that staff.  Nothing else in the drawing does both — the rule joining
    /// a system's staves at the left edge is drawn *at* `left`, not before it — and the
    /// test cannot simply take the leftmost staff edge as the threshold, because the
    /// opening system is indented further than the rest by its longer voice names.
    private func bracketSpines(in svg: String, staves: [SystemGeometry]) -> [Stroke] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"/)
            .compactMap { match in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      abs(x1 - x2) < 1e-9 else { return nil }
                let stroke = Stroke(x: x1, y1: min(y1, y2), y2: max(y1, y2))
                guard let opened = staves.first(where: { abs($0.topY - stroke.y1) < 1e-3 }),
                      stroke.x < opened.left - 1e-9 else { return nil }
                return stroke
            }
            .sorted { $0.y1 < $1.y1 }
    }

    /// The staves each bracket spans, top to bottom — the tune's systems, recovered from
    /// what was drawn rather than assumed from the voice count.
    private func systems(staves: [SystemGeometry], brackets: [Stroke]) -> [[SystemGeometry]] {
        brackets.map { bracket in
            staves.filter { $0.topY >= bracket.y1 - 0.5 && $0.bottomY <= bracket.y2 + 0.5 }
        }
    }

    // MARK: - Diagnostics

    @Test("§14.4 renders without a single warning or error")
    func rendersClean() throws {
        // Everything above `info` — the unsupported abcm2ps page-layout directives the tune
        // opens with are reported at `info` and are not a failure to parse it.
        let complaints = try render().diagnostics.filter { $0.severity != .info }
        #expect(complaints.isEmpty,
                "Unexpected diagnostics: \(complaints.map { "line \($0.source.line): \($0.message)" })")
    }

    // MARK: - Systems

    @Test("Three systems of three staves, and every staff belongs to one")
    func threeStavesPerSystem() throws {
        let (svg, staves, _) = try render()
        let brackets = bracketSpines(in: svg, staves: staves)
        #expect(brackets.count == 3)
        let systems = systems(staves: staves, brackets: brackets)
        #expect(systems.map(\.count) == [3, 3, 3])
        // No staff drawn outside a system, and none counted twice.
        #expect(systems.reduce(0) { $0 + $1.count } == staves.count)
        #expect(staves.count == 9)
    }

    @Test("The staves of a system share one x-span")
    func stavesOfASystemShareAnXSpan() throws {
        let (svg, staves, _) = try render()
        for system in systems(staves: staves, brackets: bracketSpines(in: svg, staves: staves)) {
            #expect(Set(system.map(\.left)).count == 1)
            #expect(Set(system.map(\.right)).count == 1)
        }
    }

    @Test("Bar lines are aligned across all three staves of a system")
    func barLinesAlignAcrossTheSystem() throws {
        let (svg, staves, _) = try render()
        for (index, system) in systems(staves: staves,
                                       brackets: bracketSpines(in: svg, staves: staves)).enumerated() {
            guard let top = system.first else { Issue.record("System \(index) has no staves"); return }
            #expect(!top.barlineXs.isEmpty)
            for staff in system.dropFirst() {
                #expect(staff.barlineXs.count == top.barlineXs.count,
                        "System \(index): \(staff.barlineXs.count) bar lines against \(top.barlineXs.count)")
                for (x, expected) in zip(staff.barlineXs, top.barlineXs) {
                    #expect(abs(x - expected) < 0.5,
                            "System \(index): bar line at \(x) against \(expected)")
                }
            }
        }
    }

    @Test("Each system carries one bracket, spanning all three of its staves")
    func oneBracketPerSystemSpanningIt() throws {
        let (svg, staves, _) = try render()
        let brackets = bracketSpines(in: svg, staves: staves)
        let systems = systems(staves: staves, brackets: brackets)
        for (bracket, system) in zip(brackets, systems) {
            guard let first = system.first, let last = system.last else {
                Issue.record("A bracket spans no staves")
                return
            }
            // Top staff line of the first staff to bottom staff line of the last.
            #expect(abs(bracket.y1 - first.topY) < 1e-3)
            #expect(abs(bracket.y2 - last.bottomY) < 1e-3)
            // Standing in the indent reserved for it: left of the staves, inside the margin.
            #expect(bracket.x < first.left)
            #expect(bracket.x >= config.margins.left)
        }
    }

    @Test("The abcLine anchors run down the page")
    func abcLineAnchorsAreMonotonic() throws {
        let result = CeolKitParser().parse(canzonettaABC, options: .default)
        var diagnostics: [Diagnostic] = []
        let pages = try SVGRenderer(config: config).render(result.score, diagnostics: &diagnostics)
        for page in try SVGGeometry.pages(from: pages) {
            let lines = page.systems.compactMap(\.abcLine)
            #expect(lines.count == page.systems.count, "Some system carries no anchor")
            #expect(lines == lines.sorted(), "Anchors out of order: \(lines)")
        }
    }

    // MARK: - Variant endings (§4.19)

    @Test("The last system carries the |1 and |2 brackets on all three staves")
    func variantEndingsAreDrawnOnEveryStaff() throws {
        let (svg, staves) = try textRender()
        // The tune's last stave ends `|1F2z2:|2F8|]` in every voice, so its three staves —
        // the last three drawn — each carry a `1` bracket and a `2` bracket.
        let lastSystem = staves.suffix(3)
        #expect(lastSystem.count == 3)

        for (index, staff) in lastSystem.enumerated() {
            let ruleY = staff.topY - EndingBracketBand.height(staffSize: staff.staffLineGap)
                + EndingBracketBand.thickness(metadata: try BravuraMetadata.load(),
                                              staffSize: staff.staffLineGap) / 2
            let baselineY = ruleY + EndingBracketBand.labelBaselineOffset(
                staffSize: staff.staffLineGap)
            let labels = lyricRuns(in: svg)
                .filter { abs($0.y - baselineY) < 1e-6 }
                .sorted { $0.x < $1.x }
                .map(\.content)
            #expect(labels == ["1", "2"], "Staff \(index) of the last system carries \(labels)")
        }
    }

    // MARK: - Lyrics (§4.18)

    @Test("Both verses are drawn, the second under the first")
    func bothVersesAreDrawn() throws {
        let (svg, staves) = try textRender()
        let words = lyricRuns(in: svg)
        // "Son" opens verse 1 and "Que-sti" verse 2, on the tune's very first stave.
        guard let son = words.first(where: { $0.content == "Son" }),
              let questi = words.first(where: { $0.content == "Que" }) else {
            Issue.record("Expected both verses on the page"); return
        }
        #expect(questi.y > son.y, "The second verse is not below the first")
        #expect(abs(questi.x - son.x) < 1e-6, "Both verses open under the same note")
        // Both stand below the staff they belong to — the first system's top one, since
        // that is where the tune's first sung note is.
        guard let staff = staves.first else { Issue.record("Nothing was drawn"); return }
        #expect(son.y > staff.bottomY, "The first verse was drawn on the staff")
    }

    @Test("A tilde is set as the space it stands for")
    func tildeBecomesASpace() throws {
        let words = lyricRuns(in: try textRender().svg).map(\.content)
        #expect(words.contains("sti i"), "`que-sti~i` should print as two words on one note")
        #expect(!words.contains(where: { $0.contains("~") }))
    }

    @Test("The w: continued across the line break is one verse, not two")
    func continuedLyricIsOneVerse() throws {
        let words = lyricRuns(in: try textRender().svg)
        // §14.4 writes `w: … che que-sto\\` and continues it with `w: sol de-si-o_.` after
        // the continued music line.  Joined, "que-sto" and "sol" share one baseline.
        guard let questo = words.first(where: { $0.content == "sto" && $0.x > 0 }),
              let sol = words.first(where: { $0.content == "sol" }) else {
            Issue.record("Expected both halves of the continued verse"); return
        }
        #expect(words.allSatisfy { !$0.content.contains("\\") }, "A continuation mark was printed")
        #expect(abs(sol.y - questo.y) < 1e-6 || sol.x > questo.x)
    }

    /// The same page, drawn as `<text>` rather than outlines, so the words can be read back
    /// out of it.  Placement is identical either way — only the form the runs take differs.
    private func textRender() throws -> (svg: String, staves: [SystemGeometry]) {
        let result = CeolKitParser().parse(canzonettaABC, options: .default)
        var diagnostics = result.score.diagnostics
        let pages = try textProbeRenderer(config).render(result.score, diagnostics: &diagnostics)
        return (pages.joined(), try SVGGeometry.pages(from: pages).flatMap(\.systems))
    }

    /// The words on the page: `<text>` runs in the text face, which is everything but the
    /// music itself.  The title block is set in it too and is filtered out by the callers,
    /// which ask only about what stands below a staff.
    private func lyricRuns(in svg: String) -> [(x: Double, y: Double, content: String)] {
        svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Libertinus Serif"[^>]*>([^<]*)<\/text>/
        ).compactMap { match in
            guard let x = Double(match.1), let y = Double(match.2) else { return nil }
            return (x: x, y: y, content: String(match.3))
        }
    }

    // MARK: - Snapshot

    @Test("The engraved page does not drift")
    func pageMatchesSnapshot() throws {
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

/// §14.4 of the ABC v2.2 standard, verbatim.  The backslashes are escaped for Swift: the
/// music line ends `|\` and the `w:` after it ends `que-sto\`.
private let canzonettaABC = """
%abc-2.1
%%pagewidth      21cm
%%pageheight     29.7cm
%%topspace       0.5cm
%%topmargin      1cm
%%botmargin      0cm
%%leftmargin     1cm
%%rightmargin    1cm
%%titlespace     0cm
%%titlefont      Times-Bold 32
%%subtitlefont   Times-Bold 24
%%composerfont   Times 16
%%vocalfont      Times-Roman 14
%%staffsep       60pt
%%sysstaffsep    20pt
%%musicspace     1cm
%%vocalspace     5pt
%%measurenb      0
%%barsperstaff   5
%%scale          0.7
X: 1
T: Canzonetta a tre voci
C: Claudio Monteverdi (1567-1643)
M: C
L: 1/4
Q: "Andante mosso" 1/4 = 110
%%score [1 2 3]
V: 1 clef=treble name="Soprano" sname="A"
V: 2 clef=treble name="Alto"    sname="T"
V: 3 clef=bass   name="Tenor"   sname="B" octave=-2
%%MIDI program 1 75
%%MIDI program 2 75
%%MIDI program 3 75
K: Eb
% 1 - 4
[V: 1] |:z4  |z4  |f2ec         |_ddcc        |
w: Son que-sti~i cre-spi cri-ni~e
w: Que-sti son gli~oc-chi che mi-
[V: 2] |:c2BG|AAGc|(F/G/A/B/)c=A|B2AA         |
w: Son que-sti~i cre-spi cri-ni~e que - - - - sto~il vi-so e
w: Que-sti son~gli oc-chi che mi-ran - - - - do fi-so mi-
[V: 3] |:z4  |f2ec|_ddcf        |(B/c/_d/e/)ff|
w: Son que-sti~i cre-spi cri-ni~e que - - - - sto~il
w: Que-sti son~gli oc-chi che mi-ran - - - - do
% 5 - 9
[V: 1] cAB2     |cAAA |c3B|G2!fermata!Gz ::e4|
w: que-sto~il vi-so ond' io ri-man-go~uc-ci-so. Deh,
w: ran-do fi-so, tut-to re-stai con-qui-so.
[V: 2] AAG2     |AFFF |A3F|=E2!fermata!Ez::c4|
w: que-sto~il vi-so ond' io ri-man-go~uc-ci-so. Deh,
w: ran-do fi-so tut-to re-stai con-qui-so.
[V: 3] (ag/f/e2)|A_ddd|A3B|c2!fermata!cz ::A4|
w: vi - - - so ond' io ti-man-go~uc-ci-so. Deh,
w: fi - - - so tut-to re-stai con-qui-so.
% 10 - 15
[V: 1] f_dec |B2c2|zAGF  |\\
w: dim-me-lo ben mi-o, che que-sto\\
=EFG2          |1F2z2:|2F8|]
w: sol de-si-o_.
[V: 2] ABGA  |G2AA|GF=EF |(GF3/2=E//D//E)|1F2z2:|2F8|]
w: dim-me-lo ben mi-o, che que-sto sol de-si - - - - o_.
[V: 3] _dBc>d|e2AF|=EFc_d|c4             |1F2z2:|2F8|]
w: dim-me-lo ben mi-o, che que-sto sol de-si-o_.
"""
