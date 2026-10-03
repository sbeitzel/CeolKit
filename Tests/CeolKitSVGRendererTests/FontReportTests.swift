//
//  FontReportTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #191: which fonts the renderer could use, and which each kind of text got.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("Font reports (#191)")
struct FontReportTests {

    private func render(_ abc: String, config: SVGRenderConfig = SVGRenderConfig())
        throws -> (document: RenderedDocument, diagnostics: [Diagnostic]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics = score.diagnostics
        let document = try SVGRenderer(config: config).renderDocument(score, diagnostics: &diagnostics)
        return (document, diagnostics)
    }

    private let plain = "X:1\nT:Title\nC:Composer\nK:C\n\"Am\"CDEF|]\n"

    // MARK: - Available faces

    @Test("With nothing registered and no system lookup, the bundled faces are available")
    func bundledOnly() {
        let faces = CeolKitFonts.availableFaces(config: SVGRenderConfig())
        #expect(faces.map(\.postScriptName) == [
            "Bravura", "LibertinusSerif-Regular", "LibertinusSerif-Italic",
            "LibertinusSerif-Bold", "LibertinusSerif-BoldItalic"])
        #expect(faces.allSatisfy { $0.origin == .bundled && $0.format == .cff && $0.embeddable })
        let boldItalic = faces.last
        #expect(boldItalic?.weight == .bold)
        #expect(boldItalic?.style == .italic)
        #expect(boldItalic?.family == "Libertinus Serif")
    }

    @Test("Registered faces come first, as a request searches them")
    func registered() throws {
        let url = try #require(Bundle.module.url(forResource: "CeolKitTest", withExtension: "ttc"))
        var config = SVGRenderConfig()
        config.fontLibrary = try FontLibrary(fonts: [try Data(contentsOf: url)])
        let faces = CeolKitFonts.availableFaces(config: config)
        let registered = faces.prefix { $0.origin == .registered }
        #expect(registered.count == config.fontLibrary?.postScriptNames.count)
        #expect(registered.allSatisfy { $0.format == .trueType })
        #expect(faces.count == registered.count + CeolKitFonts.Face.allCases.count)
    }

    @Test("System lookup lists the installed faces between registered and bundled ones")
    func system() {
        var config = SVGRenderConfig()
        config.systemFonts = true
        let faces = CeolKitFonts.availableFaces(config: config)
        #expect(faces.suffix(CeolKitFonts.Face.allCases.count).allSatisfy { $0.origin == .bundled })
        #if canImport(CoreText)
        // Hidden from CoreText's collection, so found by name: a document asking for
        // Courier must see it listed.
        #expect(faces.contains { $0.origin == .system && $0.postScriptName == "Courier" })
        #endif
        // Linux lists what fontconfig has, which depends on the machine; FontconfigTests
        // checks it against fonts known to be installed.
    }

    // MARK: - Resolution report

    @Test("A tune naming no font reports every kind of text at its default")
    func defaults() throws {
        let fonts = try render(plain).document.fonts
        #expect(fonts.map(\.tuneIndex) == [0])
        let roles = try #require(fonts.first?.roles)
        #expect(roles.map(\.role) == [.title, .subtitle, .composer, .tempo, .chordSymbol,
                                      .annotation, .info, .vocal, .words])
        #expect(roles.allSatisfy { $0.requested == nil && $0.source == nil })
        #expect(roles.allSatisfy { $0.resolution.origin == .bundled && $0.resolution.isExact })
        let composer = try #require(roles.first { $0.role == .composer })
        #expect(composer.resolution.postScriptName == "LibertinusSerif-Italic")
        #expect(composer.summary == "composerfont → LibertinusSerif-Italic 10.50 (bundled, default)")
    }

    @Test("A font directive's request, source and substitute are reported")
    func directive() throws {
        let abc = "%%titlefont Times-Bold 20\n" + plain
        let roles = try #require(try render(abc).document.fonts.first?.roles)
        let title = try #require(roles.first { $0.role == .title })
        #expect(title.requested == FontSpec(name: "Times-Bold", size: 20))
        #expect(title.source?.line == 1)
        // The size drawn: the 20 asked for, at the default `%%scale 0.75` (issue #203).
        #expect(title.size == 15)
        #expect(title.resolution.postScriptName == "LibertinusSerif-Bold")
        #expect(!title.resolution.isExact)
        #expect(title.summary
                == "titlefont Times-Bold 20 → LibertinusSerif-Bold 15 (bundled, substituted)")
        #expect(roles.filter { $0.requested != nil }.map(\.role) == [.title])
    }

    @Test("Each tune reports its own fonts")
    func perTune() throws {
        let abc = plain + "\nX:2\nT:Two\n%%gchordfont * 16\nK:C\n\"G\"C|]\n"
        let fonts = try render(abc).document.fonts
        #expect(fonts.map(\.tuneIndex) == [0, 1])
        func chord(_ tune: Int) -> Double? {
            fonts[tune].roles.first { $0.role == .chordSymbol }?.size
        }
        #expect(chord(0) == 9)     // abcm2ps's 12, at the default `%%scale 0.75`
        #expect(chord(1) == 12)
    }

    // MARK: - %%ceolkit:fontlist

    private func notes(_ abc: String) throws -> [Diagnostic] {
        try render(abc).diagnostics.filter { $0.code == .fontList }
    }

    @Test("A list in a tune reports the fonts the whole tune is set in, at the directive")
    func tuneList() throws {
        let abc = "X:1\nT:t\n%%ceolkit:fontlist\nK:C\nC|\n%%wordsfont Times-Bold 14\nD|]\n"
        let found = try notes(abc)
        #expect(found.count == 9)
        #expect(found.allSatisfy { $0.severity == .info && $0.source.line == 3 })
        // The body directive below the list still sets the tune's words.
        #expect(found.contains { $0.message.hasPrefix("wordsfont Times-Bold 14 →") })
    }

    @Test("A list in the preamble reports the document's baseline, not a tune's")
    func preambleList() throws {
        let abc = "%%vocalfont * 14\n%%ceolkit:fontlist\n\nX:1\nT:t\n%%vocalfont * 20\nK:C\nC|]\n"
        let found = try notes(abc)
        #expect(found.allSatisfy { $0.source.line == 2 })
        #expect(found.contains { $0.message.hasPrefix("vocalfont 14 →") })
        #expect(!found.contains { $0.message.contains("vocalfont 20") })
    }

    @Test("A list with no directive reports nothing; one per directive otherwise")
    func listCount() throws {
        #expect(try notes(plain).isEmpty)
        let twice = "X:1\nT:t\n%%ceolkit:fontlist\nK:C\nC|\n%%ceolkit:fontlist\nD|]\n"
        #expect(try notes(twice).count == 18)
    }

    @Test("An available list names every face the renderer could use")
    func availableList() throws {
        let found = try notes("X:1\nT:t\n%%ceolkit:fontlist available\nK:C\nC|]\n")
        #expect(found.map { $0.message.prefix { $0 != ":" } } == [
            "Bravura", "LibertinusSerif-Regular", "LibertinusSerif-Italic",
            "LibertinusSerif-Bold", "LibertinusSerif-BoldItalic"])
    }

    @Test("A list changes nothing on the page")
    func layoutUnchanged() throws {
        let with = try render("X:1\nT:t\n%%ceolkit:fontlist\nK:C\nC|]\n").document.pages
        let without = try render("X:1\nT:t\n% no list\nK:C\nC|]\n").document.pages
        #expect(with == without)
    }
}
