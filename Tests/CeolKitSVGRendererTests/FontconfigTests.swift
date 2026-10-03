//
//  FontconfigTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #206: on Linux, system font lookup goes through fontconfig, loaded with `dlopen`.
//
//  Most of these need fonts we know are installed, so they run only where the environment
//  says so: the CI Linux job installs fontconfig, a chosen set of packages and the
//  `CeolKitTest.ttc` fixture, and sets CEOLKIT_FONT_FIXTURES=1 (see `.github/workflows/ci.yml`).
//  Elsewhere they are skipped, not failed.
//

#if !canImport(CoreText)
import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

private let fixturesInstalled = ProcessInfo.processInfo.environment["CEOLKIT_FONT_FIXTURES"] == "1"

@Suite("System fonts through fontconfig (#206)")
struct FontconfigTests {

    private func render(_ abc: String, textRendering: TextRendering = .outlines)
        throws -> (document: RenderedDocument, diagnostics: [Diagnostic]) {
        var config = SVGRenderConfig(textRendering: textRendering)
        config.systemFonts = true
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics = score.diagnostics
        let document = try SVGRenderer(config: config).renderDocument(score, diagnostics: &diagnostics)
        return (document, diagnostics)
    }

    private func words(_ font: String) -> String {
        "%%wordsfont \(font) 14\nX:1\nT:t\nK:C\nC|]\nW:some words\n"
    }

    private func wordsReport(_ font: String, textRendering: TextRendering = .outlines)
        throws -> (TextFontReport, [Diagnostic]) {
        let (document, diagnostics) = try render(words(font), textRendering: textRendering)
        let report = try #require(document.fonts.first?.roles.first { $0.role == .words })
        return (report, diagnostics)
    }

    // MARK: - Without fixtures

    @Test("A family that is not installed finds nothing, never fontconfig's nearest guess")
    func absentFamily() throws {
        #expect(SystemFonts.faces(family: "CeolKit No Such Family").isEmpty)
        #expect(SystemFonts.faces(postScriptName: "CeolKitNoSuchFace-Bold").isEmpty)
        let (report, _) = try wordsReport("CeolKitNoSuchFace-Bold")
        #expect(report.resolution.origin == .bundled)
        #expect(report.resolution.postScriptName == "LibertinusSerif-Bold")
    }

    // MARK: - With fixtures

    @Test("A face named by PostScript name is drawn from the system",
          .enabled(if: fixturesInstalled), arguments: [
              ("EBGaramond12-Bold", FontWeight.bold, FontStyle.upright),     // CFF .otf
              ("EBGaramond12-Italic", .regular, .italic),
              ("LiberationMono-Bold", .bold, .upright),                       // TrueType
              ("NimbusRoman-Regular", .regular, .upright),                    // .otf beside Type 1
              ("CeolKitTest-Regular", .regular, .upright),                    // .ttc face 0
          ])
    func byPostScriptName(_ name: String, _ weight: FontWeight, _ style: FontStyle) throws {
        let (report, diagnostics) = try wordsReport(name)
        #expect(report.resolution.origin == .system)
        #expect(report.resolution.postScriptName == name)
        #expect(report.resolution.weight == weight)
        #expect(report.resolution.style == style)
        #expect(report.resolution.isExact)
        #expect(!diagnostics.contains { $0.code == .fontSubstituted })
    }

    @Test("Times-Bold is answered by Liberation Serif Bold, with a note",
          .enabled(if: fixturesInstalled))
    func standIn() throws {
        let (report, diagnostics) = try wordsReport("Times-Bold")
        #expect(report.resolution.origin == .system)
        #expect(report.resolution.postScriptName == "LiberationSerif-Bold")
        let note = diagnostics.first { $0.code == .fontSubstituted }
        #expect(note?.severity == .info)
    }

    @Test("A family is found in the weight and style asked for", .enabled(if: fixturesInstalled))
    func byFamily() {
        let faces = SystemFonts.faces(family: "EB Garamond")
        #expect(faces.contains { $0.postScriptName == "EBGaramond12-Bold" && $0.weightClass >= 600 })
        #expect(faces.contains { $0.postScriptName == "EBGaramond12-Italic" && $0.isItalic })
    }

    @Test("A collection's second face is read at its own index", .enabled(if: fixturesInstalled))
    func collectionIndex() throws {
        // Restricted embedding: usable as `<text>`, refused as outlines.
        let (asText, _) = try wordsReport("CeolKitTest-Restricted", textRendering: .fontFace)
        #expect(asText.resolution.postScriptName == "CeolKitTest-Restricted")
        #expect(asText.resolution.origin == .system)

        let (asOutlines, diagnostics) = try wordsReport("CeolKitTest-Restricted")
        #expect(asOutlines.resolution.postScriptName != "CeolKitTest-Restricted")
        #expect(asOutlines.resolution.refusedForEmbedding == ["CeolKitTest-Restricted"])
        #expect(diagnostics.contains { $0.code == .fontNotEmbeddable })
    }

    @Test("The listing names the installed faces, and leaves out Type 1",
          .enabled(if: fixturesInstalled))
    func listing() throws {
        var config = SVGRenderConfig()
        config.systemFonts = true
        let system = CeolKitFonts.availableFaces(config: config).filter { $0.origin == .system }
        func face(_ name: String) throws -> FontFaceInfo {
            try #require(system.first { $0.postScriptName == name }, "\(name) not listed")
        }

        let regular = try face("CeolKitTest-Regular")
        #expect(regular.format == .trueType)
        #expect(regular.embeddable)
        #expect(try !face("CeolKitTest-Restricted").embeddable)

        let bold = try face("LiberationSerif-Bold")
        #expect(bold.family == "Liberation Serif")
        #expect(bold.weight == .bold)
        #expect(bold.style == .upright)

        let italic = try face("EBGaramond12-Italic")
        #expect(italic.format == .cff)
        #expect(italic.style == .italic)

        // URW base 35 installs each face as an .otf and twice as Type 1; only the .otf is
        // one CeolKit can read.
        #expect(system.filter { $0.postScriptName == "NimbusRoman-Regular" }.count == 1)
        #expect(try face("NimbusRoman-Regular").format == .cff)

        // Both faces of the WenQuanYi collection.
        #expect(system.filter { $0.family.hasPrefix("WenQuanYi") }.count >= 2)
    }
}
#endif
