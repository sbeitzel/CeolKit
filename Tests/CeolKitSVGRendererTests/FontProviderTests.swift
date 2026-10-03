//
//  FontProviderTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #190: text can be drawn in faces the host registers and, where enabled, faces
//  installed on the system, with the bundled faces as the fallback that always answers.
//

import CeolKitModel
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("Font lookup: registered, system and bundled faces (#190)")
struct FontProviderTests {

    private static func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }

    private static func library(_ files: [(String, String)]) throws -> FontLibrary {
        try FontLibrary(fonts: files.map { try fixture($0.0, $0.1) })
    }

    private let here = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)

    // MARK: - Requests

    @Test("PostScript names split into family, weight and style",
          arguments: [
            ("Times-Roman", "Times", FontWeight.regular, FontStyle.upright),
            ("Times-BoldItalic", "Times", .bold, .italic),
            ("Helvetica-Oblique", "Helvetica", .regular, .italic),
            ("Courier-Bold", "Courier", .bold, .upright),
            ("Helvetica", "Helvetica", .regular, .upright),
            ("CeolKitTest-Restricted", "CeolKitTest-Restricted", .regular, .upright),
          ])
    func postScriptNames(_ name: String, _ family: String, _ weight: FontWeight,
                         _ style: FontStyle) {
        let request = FontRequest(postScriptName: name)
        #expect(request.family == family && request.weight == weight && request.style == style)
        #expect(request.postScriptName == name)
    }

    @Test("The base 14 and the generic families have stand-ins; other families do not")
    func aliases() {
        #expect(FontRequest(family: "serif").aliases.first == "Times")
        #expect(FontRequest(postScriptName: "Helvetica-Bold").aliases.contains("Arial"))
        #expect(FontRequest(family: "monospace").aliases.contains("Liberation Mono"))
        #expect(FontRequest(family: "Gill Sans").aliases.isEmpty)
    }

    // MARK: - Registered faces

    @Test("A registered face is drawn when named, by PostScript name or by family")
    func registeredFaceIsDrawn() throws {
        let library = try Self.library([("CeolKitTest-Short", "ttf")])
        #expect(library.postScriptNames == ["CeolKitTest-Regular"])
        for request in [FontRequest(postScriptName: "CeolKitTest-Regular"),
                        FontRequest(family: "CeolKitTest")] {
            let text = try TextOutliner.outline("A", font: request, fontSize: 1000,
                                                library: library)
            let resolution = try #require(text.resolution)
            #expect(resolution.origin == .registered)
            #expect(resolution.postScriptName == "CeolKitTest-Regular")
            #expect(resolution.isExact)
            #expect(resolution.diagnostics(at: here).isEmpty)
            // The fixture's "A", not Libertinus's.
            #expect(text.svg.contains("M0 0L300 700L600 0Z"))
            #expect(text.advanceWidth == 700)
        }
    }

    @Test("A registered face in another style answers, and says it is a substitute")
    func nearestStyleInFamily() throws {
        let library = try Self.library([("CeolKitTest-Short", "ttf")])
        let text = try TextOutliner.outline(
            "A", font: FontRequest(family: "CeolKitTest", weight: .bold), fontSize: 12,
            library: library)
        let resolution = try #require(text.resolution)
        #expect(resolution.origin == .registered)
        #expect(!resolution.isExact)
        #expect(resolution.diagnostics(at: here).map(\.code) == [.fontSubstituted])
    }

    @Test("A face whose licence forbids embedding is passed over, with a diagnostic")
    func restrictedFaceIsRefused() throws {
        let library = try Self.library([("CeolKitTest", "ttc")])
        let text = try TextOutliner.outline(
            "A", font: FontRequest(postScriptName: "CeolKitTest-Restricted"), fontSize: 12,
            library: library)
        let resolution = try #require(text.resolution)
        #expect(resolution.refusedForEmbedding == ["CeolKitTest-Restricted"])
        #expect(resolution.postScriptName != "CeolKitTest-Restricted")
        let codes = resolution.diagnostics(at: here).map(\.code)
        #expect(codes.contains(.fontNotEmbeddable))
        #expect(codes.contains(.fontSubstituted))
    }

    @Test("A font file the parser cannot read is refused by position")
    func unreadableLibraryFont() throws {
        #expect(throws: FontLibraryError.unreadableFont(index: 1)) {
            try FontLibrary(fonts: [try Self.fixture("CeolKitTest-Short", "ttf"),
                                    Data("not a font".utf8)])
        }
    }

    // MARK: - The bundled fallback

    @Test("With nothing registered and system lookup off, the bundle answers every request")
    func bundledFallback() throws {
        let text = try TextOutliner.outline(
            "A", font: FontRequest(postScriptName: "Courier-BoldOblique"), fontSize: 12)
        let resolution = try #require(text.resolution)
        #expect(resolution.origin == .bundled)
        #expect(resolution.family == "Libertinus Serif" && resolution.style == .italic)
        let diagnostics = resolution.diagnostics(at: here)
        #expect(diagnostics.map(\.code) == [.fontSubstituted])
        #expect(diagnostics.first?.message.contains("Courier-BoldOblique") == true)
    }

    @Test("The emitter's own families resolve to the bundle with the keys they always had")
    func bundledKeysUnchanged() throws {
        let provider = try FontProvider(library: try Self.library([("CeolKitTest", "ttc")]),
                                        systemFonts: true, outlinesEmbed: true)
        #expect(provider.resolve(family: "Bravura", italic: false)?.key == .bravura)
        #expect(provider.resolve(family: "Libertinus Serif", italic: true)?.key
                == .libertinusSerifItalic)
    }

    @Test("A registered face drawn by the builder gets its own glyph definitions")
    func builderDrawsRegisteredFace() throws {
        let provider = try FontProvider(library: try Self.library([("CeolKitTest-Short", "ttf")]),
                                        systemFonts: false, outlinesEmbed: true)
        var builder = SVGBuilder(textRendering: .outlines, fonts: provider)
        builder.text("AA", x: 10, y: 20, fontFamily: "CeolKitTest", fontSize: 12)
        let svg = builder.buildDocument(width: 100, height: 100, embeddedFaces: nil)
        #expect(svg.contains(#"id="f-CeolKitTest-Regular-g2""#))
        #expect(svg.components(separatedBy: "#f-CeolKitTest-Regular-g2").count - 1 == 4)
        #expect(provider.resolutions.map(\.origin) == [.registered])
    }

    @Test("Glyph keys for outside faces are valid ids and never a bundled face's")
    func faceKeys() {
        #expect(OutlineFontSet.FaceKey(postScriptName: "Times New Roman:Bold").rawValue
                == "f-Times_New_Roman_Bold")
        #expect(OutlineFontSet.FaceKey(postScriptName: "bravura") != .bravura)
    }

    // MARK: - System faces

    #if canImport(CoreText)
    private static let hasCourier = FileManager.default.fileExists(
        atPath: "/System/Library/Fonts/Courier.ttc")

    @Test("With system lookup on, Courier-Bold resolves through CoreText and is outlined",
          .enabled(if: hasCourier))
    func systemCourierBold() throws {
        let text = try TextOutliner.outline(
            "Ag", font: FontRequest(postScriptName: "Courier-Bold"), fontSize: 12,
            systemFonts: true)
        let resolution = try #require(text.resolution)
        #expect(resolution.origin == .system)
        #expect(resolution.postScriptName == "Courier-Bold")
        #expect(resolution.isExact && resolution.weight == .bold)
        #expect(!text.svg.isEmpty)
        // Courier is monospaced: both glyphs advance the same, 0.6 em.
        #expect(abs(text.advanceWidth - 2 * 0.6 * 12) < 0.01)
    }

    @Test("A generic family is answered by its stand-in, as a note rather than a warning",
          .enabled(if: FileManager.default.fileExists(atPath: "/System/Library/Fonts/Times.ttc")))
    func genericSerif() throws {
        let text = try TextOutliner.outline(
            "A", font: FontRequest(family: "serif", style: .italic), fontSize: 12,
            systemFonts: true)
        let resolution = try #require(text.resolution)
        #expect(resolution.origin == .system)
        #expect(resolution.postScriptName == "Times-Italic")
        let diagnostics = resolution.diagnostics(at: here)
        #expect(diagnostics.map(\.code) == [.fontSubstituted])
        #expect(diagnostics.first?.severity == .info)
    }

    @Test("System lookup is off by default", .enabled(if: hasCourier))
    func systemLookupOffByDefault() throws {
        #expect(SVGRenderConfig().systemFonts == false)
        let text = try TextOutliner.outline(
            "A", font: FontRequest(postScriptName: "Courier-Bold"), fontSize: 12)
        #expect(text.resolution?.origin == .bundled)
    }

    @Test("A family that is not installed is not answered by CoreText's fallback")
    func missingSystemFamily() throws {
        let text = try TextOutliner.outline(
            "A", font: FontRequest(family: "No Such Family Anywhere"), fontSize: 12,
            systemFonts: true)
        #expect(text.resolution?.origin == .bundled)
    }
    #endif
}
