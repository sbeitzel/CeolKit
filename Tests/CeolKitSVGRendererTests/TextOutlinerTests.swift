import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import Testing
@testable import CeolKitSVGRenderer

// MARK: - Helpers

/// Element names and attributes of a fragment, read by a real XML parser so a malformed
/// fragment fails here rather than in a caller's rasteriser.
private final class FragmentReader: NSObject, XMLParserDelegate {
    var elements: [(name: String, attributes: [String: String])] = []

    static func read(_ fragment: String) throws -> [(name: String, attributes: [String: String])] {
        // The fragment is meant to sit inside a caller's document, so parse it inside one.
        let document = "<svg xmlns=\"http://www.w3.org/2000/svg\">\(fragment)</svg>"
        let parser = XMLParser(data: Data(document.utf8))
        let reader = FragmentReader()
        parser.delegate = reader
        guard parser.parse() else {
            throw parser.parserError ?? CocoaError(.coderReadCorrupt)
        }
        return Array(reader.elements.dropFirst())
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        elements.append((elementName, attributeDict))
    }
}

/// The `transform` of every glyph a string of elements draws, in order.
private func transforms(in markup: String) -> [String] {
    markup.components(separatedBy: "transform=\"").dropFirst()
        .map { String($0.prefix(while: { $0 != "\"" })) }
}

// MARK: - Tests

@Suite("Public text outlining")
struct TextOutlinerTests {

    @Test func fragmentIsSelfContainedWellFormedMarkup() throws {
        let outlined = try TextOutliner.outline("Reels & Jigs", face: .libertinusSerifRegular,
                                                fontSize: 24)
        let elements = try FragmentReader.read(outlined.svg)

        #expect(elements.first?.name == "g")
        #expect(elements.first?.attributes["fill"] == "black")
        #expect(elements.dropFirst().allSatisfy { $0.name == "path" })
        for element in elements {
            #expect(element.attributes["id"] == nil)
        }
        #expect(!outlined.svg.contains("<use"))
        #expect(!outlined.svg.contains("<text"))
        #expect(!outlined.svg.contains("href"))
        #expect(!outlined.svg.contains("<defs"))
    }

    /// Spaces advance the pen but draw nothing, so only inked glyphs get a path — and a
    /// repeated glyph gets one each time, since there is no `<defs>` to share.
    @Test func onePathPerInkedGlyph() throws {
        let outlined = try TextOutliner.outline("a a a", face: .libertinusSerifRegular,
                                                fontSize: 12)
        let paths = try FragmentReader.read(outlined.svg).filter { $0.name == "path" }
        #expect(paths.count == 3)
        #expect(Set(paths.compactMap { $0.attributes["d"] }).count == 1)
    }

    @Test func advanceWidthIsTheMeasureLayoutUses() throws {
        let text = "The Kesh Jig — Ó Riada"
        let font = try OutlineFontSet.font(for: .libertinusSerifRegular)
        let outlined = try TextOutliner.outline(text, face: .libertinusSerifRegular, fontSize: 18)

        #expect(outlined.advanceWidth == font.width(of: text, fontSize: 18))
        #expect(outlined.advanceWidth ==
                (try TextOutliner.width(of: text, face: .libertinusSerifRegular, fontSize: 18)))
        #expect(outlined.advanceWidth > 0)
    }

    /// The contract in the issue: the public API and the engraver never place a run
    /// differently. Draw the same run both ways and compare every glyph's transform.
    @Test(arguments: [CeolKitFonts.Face.libertinusSerifRegular, .libertinusSerifItalic])
    func glyphsSitWhereTheEngraverPutsThem(face: CeolKitFonts.Face) throws {
        let text = "Tripping Up the Stairs"
        var builder = SVGBuilder(textRendering: .outlines, fonts: try OutlineFontSet.shared())
        builder.text(text, x: 0, y: 0, fontFamily: face.familyName, fontSize: 21,
                     fontStyle: face.isItalic ? "italic" : nil)
        let engraved = transforms(in: builder.elements.joined())

        let outlined = try TextOutliner.outline(text, face: face, fontSize: 21)
        #expect(!engraved.isEmpty)
        #expect(transforms(in: outlined.svg) == engraved)
    }

    /// An unencoded scalar draws `.notdef` and advances by its width, rather than vanishing.
    @Test func unencodedScalarDrawsNotdef() throws {
        let font = try OutlineFontSet.font(for: .libertinusSerifRegular)
        let scalar = SMuFLGlyph.gClef.unicodeScalar
        #expect(font.glyphID(for: scalar) == nil)

        let outlined = try TextOutliner.outline(String(Character(scalar)),
                                                face: .libertinusSerifRegular, fontSize: 10)
        #expect(outlined.advanceWidth == font.advance(forGlyph: 0) * 10 / font.unitsPerEm)
        #expect(outlined.advanceWidth > 0)
        #expect(outlined.svg.contains("<path"))
    }

    @Test func libertinusVerticalMetricsMatchThePublishedRatios() throws {
        for face in [CeolKitFonts.Face.libertinusSerifRegular, .libertinusSerifItalic] {
            let outlined = try TextOutliner.outline("x", face: face, fontSize: 100)
            #expect(abs(outlined.ascent - LibertinusSerifMetrics.ascenderRatio * 100) < 1e-9)
            #expect(abs(outlined.descent - LibertinusSerifMetrics.descenderRatio * 100) < 1e-9)
        }
    }

    @Test func fillIsEscaped() throws {
        let outlined = try TextOutliner.outline("A", face: .libertinusSerifRegular, fontSize: 12,
                                                fill: "url(#a\"b)")
        let group = try #require(try FragmentReader.read(outlined.svg).first)
        #expect(group.attributes["fill"] == "url(#a\"b)")
    }

    @Test func italicAndBravuraFacesOutline() throws {
        let regular = try TextOutliner.outline("f", face: .libertinusSerifRegular, fontSize: 12)
        let italic = try TextOutliner.outline("f", face: .libertinusSerifItalic, fontSize: 12)
        #expect(!italic.svg.isEmpty)
        #expect(italic.svg != regular.svg)

        let clef = try TextOutliner.outline(String(Character(SMuFLGlyph.gClef.unicodeScalar)),
                                            face: .bravura, fontSize: 40)
        #expect(clef.svg.contains("<path"))
        #expect(clef.advanceWidth > 0)
        #expect(clef.ascent > 0)
        #expect(clef.descent > 0)
    }

    @Test func runsWithNothingToInkProduceNoMarkup() throws {
        let empty = try TextOutliner.outline("", face: .libertinusSerifRegular, fontSize: 12)
        #expect(empty.svg.isEmpty)
        #expect(empty.advanceWidth == 0)
        #expect(empty.ascent > 0)

        let spaces = try TextOutliner.outline("   ", face: .libertinusSerifRegular, fontSize: 12)
        #expect(spaces.svg.isEmpty)
        #expect(spaces.advanceWidth > 0)
    }

    /// The first glyph's pen sits at the origin, so a caller's `translate` places the run.
    @Test func runStartsAtTheOrigin() throws {
        let outlined = try TextOutliner.outline("Hello", face: .libertinusSerifRegular,
                                                fontSize: 12)
        let first = try #require(transforms(in: outlined.svg).first)
        #expect(first.hasPrefix("translate(0 0) "))
    }
}
