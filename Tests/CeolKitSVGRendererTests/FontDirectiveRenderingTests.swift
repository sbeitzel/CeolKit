//
//  FontDirectiveRenderingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #186: the §11.4.2 font directives set the face and size of each kind of text, and a
//  host's `SVGRenderConfig.textFonts` sets a house style beneath them.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("Font directives set each kind of text (#186)")
struct FontDirectiveRenderingTests {

    // MARK: - Sources and probes

    /// A tune exercising every role that draws: two titles, a composer, a rhythm (printed
    /// by `%%writefields R`), a tempo, a chord symbol, annotations above and below, a lyric,
    /// a tempo change in the music, and words.
    private func tune(_ header: String = "", preamble: String = "") -> String {
        preamble + """
        X:1
        T:Main Title
        T:Second Title
        C:Composer Name
        R:Reel
        Q:1/4=120
        M:4/4
        L:1/4
        %%writefields R
        \(header)K:C
        "Am"C "^above"D "_below"E F|[Q:1/4=90] G A B c|]
        w: sing-ing la la la
        W:words line

        """
    }

    private func render(_ abc: String, config: SVGRenderConfig = SVGRenderConfig())
        throws -> (svg: String, diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics = score.diagnostics
        let pages = try SVGRenderer(config: config).render(score, diagnostics: &diagnostics)
        return (pages.joined(), diagnostics)
    }

    private struct Run {
        let family: String, size: Double, style: String?, weight: String?, content: String
    }

    /// Every `<text>` run, in `fontFace` mode.
    private func runs(_ abc: String, config: SVGRenderConfig = SVGRenderConfig()) throws -> [Run] {
        var config = config
        config.textRendering = .fontFace
        return try render(abc, config: config).svg.matches(
            of: /<text [^>]*?font-family="([^"]+)" font-size="([-0-9.]+)"[^>]*?(?: font-style="([a-z]+)")?(?: font-weight="([a-z]+)")?>([^<]*)<\/text>/
        ).compactMap { m in
            guard let size = Double(m.2) else { return nil }
            return Run(family: String(m.1), size: size, style: m.3.map(String.init),
                       weight: m.4.map(String.init), content: String(m.5))
        }
    }

    private func run(_ content: String, in runs: [Run],
                     sourceLocation: SourceLocation = #_sourceLocation) throws -> Run {
        try #require(runs.first { $0.content == content }, "no run \"\(content)\"",
                     sourceLocation: sourceLocation)
    }

    // MARK: - Defaults

    @Test("With no directive, every kind of text is set as it always was")
    func defaultsUnchanged() throws {
        let all = try runs(tune())
        #expect(try run("Main Title", in: all).size == 18)
        #expect(try run("Second Title", in: all).size == 12)
        #expect(try run("Second Title", in: all).style == "italic")
        #expect(try run("Composer Name", in: all).style == "italic")
        #expect(try run("Am", in: all).size == 12)
        #expect(try run("words line", in: all).size == 12)
        #expect(all.allSatisfy { $0.family != "Libertinus Serif" || $0.weight == nil })
    }

    // MARK: - Sizes, role by role

    @Test("Each directive sizes its own kind of text", arguments: [
        ("titlefont", "Main Title", 30.0),
        ("subtitlefont", "Second Title", 20.0),
        ("composerfont", "Composer Name", 16.0),
        ("infofont", "Reel", 15.0),
        ("tempofont", "♩ = 120", 14.0),
        ("wordsfont", "words line", 16.0),
        ("gchordfont", "Am", 16.0),
        ("annotationfont", "above", 9.0),
        ("annotationfont", "below", 9.0),
        ("vocalfont", "la", 14.0),
    ])
    func sizes(_ directive: String, _ text: String, _ size: Double) throws {
        let all = try runs(tune(preamble: "%%\(directive) * \(size)\n"))
        #expect(try run(text, in: all).size == size)
        // `*` keeps the face: the default italic roles stay italic.
        if ["subtitlefont", "composerfont", "infofont"].contains(directive) {
            #expect(try run(text, in: all).style == "italic")
        }
    }

    @Test("Staff text scales with %%ceolkit:scale; page text does not")
    func scaling() throws {
        let all = try runs(tune(preamble: """
            %%ceolkit:scale 0.5
            %%gchordfont * 16
            %%vocalfont * 14
            %%tempofont * 14
            %%titlefont * 30
            %%wordsfont * 16

            """))
        #expect(try run("Am", in: all).size == 8)
        #expect(try run("la", in: all).size == 7)
        #expect(try run("Main Title", in: all).size == 30)
        #expect(try run("words line", in: all).size == 16)
        // The header tempo is page text, the change in the music staff text.
        #expect(try run("♩ = 120", in: all).size == 14)
        #expect(try run("♩ = 90", in: all).size == 7)
    }

    // MARK: - Faces

    @Test("A bold PostScript name sets the text bold, in the bundled bold face")
    func boldFromTheBundle() throws {
        let abc = tune(preamble: "%%composerfont Times-Bold\n")
        let composer = try run("Composer Name", in: try runs(abc))
        #expect(composer.family == "Libertinus Serif")
        #expect(composer.weight == "bold")
        #expect(composer.style == nil, "Times-Bold is upright")
        // Outlined from the bold face itself.
        #expect(try render(abc).svg.contains("libertinusSerifBold-g"))
    }

    @Test("A face the host registered is drawn when a directive names it")
    func registeredFace() throws {
        let url = try #require(Bundle.module.url(forResource: "CeolKitTest-Short", withExtension: "ttf"))
        var config = SVGRenderConfig()
        config.fontLibrary = try FontLibrary(fonts: [try Data(contentsOf: url)])
        let (svg, diagnostics) = try render(tune(preamble: "%%wordsfont CeolKitTest-Regular 14\n"),
                                            config: config)
        #expect(svg.contains("f-CeolKitTest-Regular-g"))
        #expect(!diagnostics.contains { $0.code == .fontSubstituted })
    }

    // MARK: - Scope and precedence

    @Test("A tune header overrides the file header, for that tune only")
    func tuneOverridesFile() throws {
        let two = tune(preamble: "%%gchordfont * 16\n") + "\n" + tune("%%gchordfont * 10\n")
        let chords = try runs(two).filter { $0.content == "Am" }.map(\.size)
        #expect(chords == [16, 10])
    }

    @Test("The host's house style applies, and a directive in the document still wins")
    func configOverride() throws {
        var config = SVGRenderConfig()
        config.textFonts = [.composer: FontSpec(name: "Times-Bold", size: 20),
                            .title: FontSpec(name: nil, size: 24)]
        let house = try runs(tune(), config: config)
        #expect(try run("Composer Name", in: house).weight == "bold")
        #expect(try run("Composer Name", in: house).size == 20)
        #expect(try run("Main Title", in: house).size == 24)

        let overridden = try runs(tune(preamble: "%%composerfont * 13\n"), config: config)
        let composer = try run("Composer Name", in: overridden)
        #expect(composer.size == 13)
        #expect(composer.weight == "bold", "the size-only directive keeps the house face")
    }

    // MARK: - Layout follows the text

    @Test("A larger title pushes the rows below it down")
    func titleRowGrows() throws {
        func gap(_ abc: String) throws -> Double {
            let probe = SVGRenderConfig(textRendering: .fontFace)
            let svg = try render(abc, config: probe).svg
            func y(_ text: String) -> Double? {
                svg.firstMatch(of: try! Regex("<text x=\"[-0-9.]+\" y=\"([-0-9.]+)\"[^>]*>\(text)</text>"))
                    .flatMap { Double($0.output[1].substring ?? "") }
            }
            return (y("Second Title") ?? 0) - (y("Main Title") ?? 0)
        }
        #expect(try gap(tune(preamble: "%%titlefont * 36\n")) > gap(tune()))
    }

    @Test("Larger lyrics and chord symbols take more room on the page")
    func bandsGrow() throws {
        func layout(_ abc: String) throws -> ResolvedSystem {
            let score = CeolKitParser().parse(abc, options: .default).score
            return try #require(try SVGRenderer().renderDocument(score).layout.pages.first?.systems.first)
        }
        let plain = try layout(tune())
        let large = try layout(tune(preamble: "%%gchordfont * 24\n%%vocalfont * 24\n"))
        #expect(large.extraAbove > plain.extraAbove)
        #expect(large.extraBelow > plain.extraBelow)
    }

    // MARK: - Embedding and diagnostics

    @Test("fontFace mode embeds a bundled bold face only where it is used")
    func boldEmbeddedOnlyWhenUsed() throws {
        let probe = SVGRenderConfig(textRendering: .fontFace)
        #expect(!(try render(tune(), config: probe).svg.contains("font-weight: bold")))
        #expect(try render(tune(preamble: "%%titlefont Times-Bold\n"), config: probe)
                    .svg.contains("font-weight: bold"))
    }

    @Test("A substituted font is a note at the directive, once, while system lookup is off")
    func substitutionNote() throws {
        let abc = tune(preamble: "%%wordsfont Courier-Bold 16\n") + "\n" + tune()
        let substituted = try render(abc).diagnostics.filter { $0.code == .fontSubstituted }
        #expect(substituted.count == 1)
        #expect(substituted.first?.severity == .info)
        #expect(substituted.first?.source.line == 1)
        #expect(substituted.first?.message.contains("Courier-Bold") == true)
    }
}
