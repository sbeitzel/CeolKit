//
//  FontSwitchRenderingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #204: `$1` … `$4` set the rest of a text string in the `%%setfont-n` face, `$0`
//  returns to the string's own font, and `$$` is a dollar sign (ABC v2.2 §11.4.2).
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("In-string font switches (#204)")
struct FontSwitchRenderingTests {

    // MARK: - Sources and probes

    /// A tune with a `$1` span in every kind of text CeolKit prints.
    private func tune(preamble: String = "%%setfont-1 Times-Bold 24\n") -> String {
        preamble + """
        X:1
        T:Main $1T1$0 end
        T:Second $1S1
        C:Composer $1C1
        R:Reel $1R1
        Q:"Brisk $1Q1" 1/4=120
        M:4/4
        L:1/4
        %%writefields R
        K:C
        "G$1m"C "^up $1A1"D "_down $1B1"E "<left $1L1"F|"@1,4 at $1AT"G "plain $1CL"A [Q:"slow $1QC" 1/4=90] B c|]
        w: la $1LY la la
        W:words $1W1

        """
    }

    private func render(_ abc: String, textRendering: TextRendering = .fontFace)
        throws -> (svg: String, diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics = score.diagnostics
        var config = SVGRenderConfig()
        config.textRendering = textRendering
        let pages = try SVGRenderer(config: config).render(score, diagnostics: &diagnostics)
        return (pages.joined(), diagnostics)
    }

    private func layout(_ abc: String) throws -> ResolvedLayout {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score).layout
    }

    private struct Run {
        let x: Double, family: String, size: Double, anchor: String?, style: String?
        let weight: String?, content: String
    }

    /// Every painted `<text>` run, in `fontFace` mode.
    private func runs(_ abc: String) throws -> [Run] {
        try render(abc).svg.matches(
            of: /<text x="([-0-9.]+)" y="[-0-9.]+"(?: xml:space="preserve")? font-family="([^"]+)" font-size="([-0-9.]+)" fill="black"(?: text-anchor="([a-z]+)")?(?: font-style="([a-z]+)")?(?: font-weight="([a-z]+)")?(?: class="[a-z]+")?>([^<]*)<\/text>/
        ).compactMap { m in
            guard let x = Double(m.1), let size = Double(m.3) else { return nil }
            return Run(x: x, family: String(m.2), size: size, anchor: m.4.map(String.init),
                       style: m.5.map(String.init), weight: m.6.map(String.init),
                       content: String(m.7))
        }
    }

    private func run(_ content: String, in runs: [Run],
                     sourceLocation: SourceLocation = #_sourceLocation) throws -> Run {
        try #require(runs.first { $0.content == content }, "no run \"\(content)\"",
                     sourceLocation: sourceLocation)
    }

    // MARK: - Every kind of text

    @Test("$1 sets the rest of the string in %%setfont-1, in every kind of text", arguments: [
        ("Main ", "T1"), ("Second ", "S1"), ("Composer ", "C1"), ("Reel ", "R1"),
        ("Brisk ", "Q1"), ("up ", "A1"), ("down ", "B1"), ("left ", "L1"), ("at ", "AT"),
        ("plain ", "CL"), ("G", "m"), ("slow ", "QC"), ("words ", "W1"),
    ])
    func everyRole(_ before: String, _ switched: String) throws {
        let all = try runs(tune())
        let plain = try run(before, in: all)
        let bold = try run(switched, in: all)
        // Times-Bold 24 is drawn in Libertinus Serif Bold, at the default `%%scale 0.75`.
        #expect(bold.weight == "bold")
        #expect(bold.style == nil)
        #expect(bold.size == 18)
        #expect(plain.weight == nil)
        #expect(plain.size != 18)
        // Set after the text before it, not on top of it.
        #expect(bold.x > plain.x)
        #expect(!all.contains { $0.content.contains("$") })
    }

    @Test("$1 in a w: line holds for the syllables after it")
    func lyrics() throws {
        let all = try runs(tune())
        let syllables = all.filter { $0.content == "la" }
        #expect(syllables.count == 3)
        #expect(try run("LY", in: all).size == 18)
        #expect(syllables.first?.size == 9.75)
        #expect(syllables.dropFirst().allSatisfy { $0.size == 18 && $0.weight == "bold" })
    }

    @Test("$0 returns to the string's own font")
    func reset() throws {
        let end = try run(" end", in: try runs(tune()))
        #expect(end.size == 15)
        #expect(end.weight == nil)
    }

    @Test("A centred title is centred as a whole, its runs set end to end")
    func centring() throws {
        let all = try runs(tune())
        let main = try run("Main ", in: all), t1 = try run("T1", in: all)
        let end = try run(" end", in: all)
        #expect(main.anchor == nil && t1.anchor == nil && end.anchor == nil)
        let regular = TextStyle(size: 15)
        #expect(abs(t1.x - (main.x + regular.width(ofRun: "Main "))) < 0.01)
        let right = end.x + regular.width(ofRun: " end")
        let pageWidth = SVGRenderConfig().pageSize.width
        #expect(abs((main.x + right) / 2 - pageWidth / 2) < 0.01)
    }

    @Test("A string with no switch is drawn in one run, as before")
    func noSwitch() throws {
        let all = try runs("X:1\nT:Plain Title\nK:C\nC|]\n")
        let title = try run("Plain Title", in: all)
        #expect(title.anchor == "middle")
    }

    // MARK: - Dollars and unset faces

    @Test("$$ prints a dollar sign, and $5 is printed as written")
    func dollars() throws {
        let all = try runs("X:1\nT:Costs $$1 or $5\nK:C\nC|]\n")
        #expect(try run("Costs $1 or $5", in: all).size == 15)
    }

    @Test("An unset %%setfont-n keeps the string's face at 12, with a warning")
    func unset() throws {
        let abc = "X:1\nT:Main $2Two\nT:Second $2It $2Again\nK:C\nC|]\n"
        let all = try runs(abc)
        let two = try run("Two", in: all)
        #expect(two.size == 9)
        #expect(two.style == nil && two.weight == nil)
        let italic = try run("It ", in: all)
        #expect(italic.size == 9)
        #expect(italic.style == "italic")
        let warnings = try render(abc).diagnostics.filter { $0.code == .unsetFontSwitch }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.source.line == 2)
    }

    @Test("%%setfont-n with * keeps the string's face, at its own size, without a warning")
    func starFace() throws {
        let abc = "%%setfont-2 * 20\nX:1\nT:Main\nT:Second $2It\nK:C\nC|]\n"
        let italic = try run("It", in: try runs(abc))
        #expect(italic.size == 15)
        #expect(italic.style == "italic")
        #expect(!(try render(abc).diagnostics.contains { $0.code == .unsetFontSwitch }))
    }

    // MARK: - Scope

    @Test("A tune header's %%setfont-n applies to that tune only")
    func tuneScope() throws {
        let abc = """
            X:1
            T:One $1A
            %%setfont-1 Times-Bold 24
            K:C
            C|]

            X:2
            T:Two $1B
            K:C
            C|]

            """
        let all = try runs(abc)
        #expect(try run("A", in: all).size == 18)
        #expect(try run("B", in: all).size == 9)
        let warnings = try render(abc).diagnostics.filter { $0.code == .unsetFontSwitch }
        #expect(warnings.map(\.source.line) == [8])
    }

    @Test("A file header's %%setfont-n applies to every tune")
    func fileScope() throws {
        let abc = "%%setfont-1 Times-Bold 24\n\nX:1\nT:One $1A\nK:C\nC|]\n\nX:2\nT:Two $1B\nK:C\nC|]\n"
        let all = try runs(abc)
        #expect(try run("A", in: all).size == 18)
        #expect(try run("B", in: all).size == 18)
    }

    // MARK: - Footers and the layout

    @Test("A switch in a Q: field's text does not reach its metronome mark")
    func tempoMark() throws {
        let all = try runs(tune())
        #expect(try run("Q1", in: all).weight == "bold")
        #expect(try run(" ♩ = 120", in: all).size == 11.25)
        #expect(try run(" ♩ = 90", in: all).weight == nil)
    }

    @Test("A footer's $ marks are its own: $1 prints as written, $T without switches")
    func footer() throws {
        let abc = "%%setfont-1 Times-Bold 24\n%%footer \"$1x\t\t$T\"\nX:1\nT:Reel $1in D\nK:C\nC|]\n"
        let all = try runs(abc)
        #expect(all.contains { $0.content == "$1x" })
        #expect(all.contains { $0.content == "Reel in D" })
    }

    @Test("A title item's text reads without its switches")
    func plainItemText() throws {
        let page = try #require(try layout(tune()).pages.first)
        let texts = page.titleRows.flatMap(\.items).map(\.text)
        #expect(texts.contains("Main T1 end"))
        #expect(!texts.contains { $0.contains("$") })
    }

    @Test("A switch to a larger face widens the room its text is given", arguments: [
        "\"^$1annotation\"C D E F|]", "C D E F|]\nw:$1syllable x x x",
    ])
    func spacing(_ body: String) throws {
        func gap(_ preamble: String) throws -> Double {
            let abc = preamble + "X:1\nT:t\nM:4/4\nL:1/4\n%%stretchlast 0\nK:C\n" + body + "\n"
            let events = try #require(try layout(abc).pages.first?.systems.first)
                .measures[0].events
            return events[1].origin.x - events[0].origin.x
        }
        #expect(try gap("%%setfont-1 * 40\n") > gap("%%setfont-1 * 12\n"))
    }
}
