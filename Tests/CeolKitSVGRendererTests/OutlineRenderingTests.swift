import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

// MARK: - Helpers

/// A tune exercising every kind of run the emitter produces: notation glyphs, a centred
/// title, a right-anchored composer, and an italicised rhythm line.
private let sampleABC = """
    %abc-2.2
    X:1
    T:Outline Test
    C:A. Composer
    R:march
    M:4/4
    L:1/8
    K:D
    |: A>BAB cdec | d2f2 e2d2 :|
    """

private func render(_ textRendering: TextRendering, abc: String = sampleABC) throws -> [String] {
    let score = CeolKitParser().parse(abc, options: .default).score
    return try SVGRenderer(config: SVGRenderConfig(textRendering: textRendering)).render(score)
}

/// Axis-aligned bounds of an outline, with curves flattened finely enough that the sampling
/// error is orders of magnitude below the tolerance the caller compares at.
private func bounds(of path: GlyphPath) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
    var minX = Double.infinity, minY = Double.infinity
    var maxX = -Double.infinity, maxY = -Double.infinity
    var current = GlyphPath.Point(x: 0, y: 0)
    var sawPoint = false

    func include(_ p: GlyphPath.Point) {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
        sawPoint = true
    }

    for segment in path.segments {
        switch segment {
        case .move(let p), .line(let p):
            include(p)
            current = p
        case .curve(let c1, let c2, let end):
            // Sample the cubic rather than taking the control hull, which would overstate
            // the extent and make the comparison against the metadata meaningless.
            let steps = 64
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let u = 1 - t
                let x = u * u * u * current.x + 3 * u * u * t * c1.x
                      + 3 * u * t * t * c2.x + t * t * t * end.x
                let y = u * u * u * current.y + 3 * u * u * t * c1.y
                      + 3 * u * t * t * c2.y + t * t * t * end.y
                include(GlyphPath.Point(x: x, y: y))
            }
            current = end
        case .close:
            break
        }
    }
    return sawPoint ? (minX, minY, maxX, maxY) : nil
}

// MARK: - Font parsing

@Suite("OpenType outline extraction")
struct OpenTypeFontTests {

    @Test(arguments: CeolKitFonts.Face.allCases)
    func everyBundledFaceParses(face: CeolKitFonts.Face) throws {
        let font = try OpenTypeFont.parse(try CeolKitFonts.data(for: face))
        #expect(font.unitsPerEm == 1000)
        #expect(font.glyphCount > 1000)
    }

    /// Cross-checks the charstring interpreter against a source of truth that is already in
    /// the repository and was produced by different software: Bravura's own metadata records
    /// each glyph's ink extent, so a misread curve, a mishandled `hintmask`, or a dropped
    /// subroutine call moves a bound and fails here.
    ///
    /// SMuFL fixes one staff space at a quarter of the em, which is how font units convert
    /// to the staff spaces `glyphBBoxes` is expressed in.
    @Test func bravuraOutlinesMatchMetadataBoundingBoxes() throws {
        let font = try OpenTypeFont.parse(try CeolKitFonts.data(for: .bravura))
        let metadata = try BravuraMetadata.load()
        let staffSpace = font.unitsPerEm / 4

        for glyph in SMuFLGlyph.allCases {
            let expected = try #require(metadata.glyphBBoxes[glyph.rawValue],
                                        "no metadata bBox for \(glyph.rawValue)")
            let gid = try #require(font.glyphID(for: glyph.unicodeScalar),
                                   "Bravura does not encode \(glyph.rawValue)")
            let outline = try font.outline(forGlyph: gid)
            let box = try #require(bounds(of: outline), "\(glyph.rawValue) has no outline")

            // Half a font unit. The bound is loose enough only to absorb upstream's own
            // imprecision: Bravura 1.392's metadata disagrees with its outlines by up to
            // 0.0016 staff spaces on four flag glyphs (`flag8thDown` worst, at bBoxSW y
            // -0.0575672 against a true extent of -0.056) — the same four whose boxes moved
            // in the 1.38 → 1.392 bump. Any real interpreter fault — a dropped subroutine,
            // a miscounted `hintmask` — moves a bound by whole font units at minimum.
            let tolerance = 0.002
            #expect(abs(box.minX / staffSpace - expected.swX) < tolerance,
                    "\(glyph.rawValue) swX: \(box.minX / staffSpace) vs \(expected.swX)")
            #expect(abs(box.minY / staffSpace - expected.swY) < tolerance,
                    "\(glyph.rawValue) swY: \(box.minY / staffSpace) vs \(expected.swY)")
            #expect(abs(box.maxX / staffSpace - expected.neX) < tolerance,
                    "\(glyph.rawValue) neX: \(box.maxX / staffSpace) vs \(expected.neX)")
            #expect(abs(box.maxY / staffSpace - expected.neY) < tolerance,
                    "\(glyph.rawValue) neY: \(box.maxY / staffSpace) vs \(expected.neY)")
        }
    }

    @Test func resolvesLatinTextAndPrivateUseCodepoints() throws {
        let serif = try OpenTypeFont.parse(try CeolKitFonts.data(for: .libertinusSerifRegular))
        let bravura = try OpenTypeFont.parse(try CeolKitFonts.data(for: .bravura))

        // Accented characters matter: tune titles are full of them.
        for scalar in "AZaz0123456789ÓéÜß".unicodeScalars {
            let gid = try #require(serif.glyphID(for: scalar), "no glyph for \(scalar)")
            #expect(!(try serif.outline(forGlyph: gid)).isEmpty)
            #expect(serif.advance(forGlyph: gid) > 0)
        }
        #expect(bravura.glyphID(for: SMuFLGlyph.gClef.unicodeScalar) != nil)
        #expect(serif.glyphID(for: SMuFLGlyph.gClef.unicodeScalar) == nil)
    }

    /// A space has to advance the pen without contributing geometry — the case that would
    /// silently collapse multi-word titles if advances came from bounding boxes.
    @Test func spaceAdvancesWithoutAnOutline() throws {
        let serif = try OpenTypeFont.parse(try CeolKitFonts.data(for: .libertinusSerifRegular))
        let space = try #require(serif.glyphID(for: " "))
        #expect((try serif.outline(forGlyph: space)).isEmpty)
        #expect(serif.advance(forGlyph: space) > 0)
    }

    @Test func rejectsDataThatIsNotAFont() {
        #expect(throws: OpenTypeError.notAnOpenTypeFont) {
            try OpenTypeFont.parse(Data("this is not a font at all".utf8))
        }
    }
}

// MARK: - Emission

@Suite("Text-as-outlines emission")
struct OutlineEmissionTests {

    /// The mode's entire purpose: a document that carries no dependency on the host's font
    /// environment. Any surviving `<text>`, `font-family`, or `@font-face` means the mode
    /// half-applied and the output would render differently depending on the machine.
    @Test func outlineDocumentsCarryNoFontDependency() throws {
        for page in try render(.outlines) {
            #expect(!page.contains("<text"))
            #expect(!page.contains("font-family"))
            #expect(!page.contains("@font-face"))
            #expect(!page.contains("base64"))
        }
    }

    @Test func outlineDocumentsDrawGlyphsAsReusedPaths() throws {
        let page = try #require(try render(.outlines).first)
        let definitions = page.components(separatedBy: "<path id=\"").count - 1
        let uses = page.components(separatedBy: "<use ").count - 1
        #expect(definitions > 0)
        // Every drawn glyph must resolve to a definition, and a page of music repeats
        // noteheads and stems enough that reuse is the whole point of the `<defs>` block.
        #expect(uses > definitions)
        #expect(page.contains("xmlns:xlink"))
        // Both spellings, because rasterisers are split on which of them they honour.
        #expect(page.contains("href=\"#"))
        #expect(page.contains("xlink:href=\"#"))
    }

    /// Each glyph is defined once no matter how often it is drawn, and at whatever size,
    /// because the size lives in the `<use>` transform rather than in the path data.
    @Test func repeatedGlyphsShareOneDefinition() throws {
        let page = try #require(try render(.outlines).first)
        var ids: [String] = []
        for chunk in page.components(separatedBy: "<path id=\"").dropFirst() {
            ids.append(String(chunk.prefix(while: { $0 != "\"" })))
        }
        #expect(ids.count == Set(ids).count, "a glyph was defined more than once")
    }

    /// Dropping ~1.5 MB of base64 more than pays for the outlines of the few dozen glyphs a
    /// page actually draws.
    @Test func outlineDocumentsAreSmallerThanEmbeddedFonts() throws {
        let outlined = try #require(try render(.outlines).first)
        let embedded = try #require(try render(.fontFace).first)
        #expect(outlined.count * 4 < embedded.count)
    }

    @Test func bothModeKeepsTheTextSelectableWithoutPaintingIt() throws {
        let page = try #require(try render(.both).first)
        #expect(page.contains("<use "))
        #expect(page.contains("@font-face"))
        #expect(page.contains("<text "))
        // Every text element is present for selection and search only; the geometry on the
        // page comes from the paths, so none of them may paint.
        for chunk in page.components(separatedBy: "<text ").dropFirst() {
            let element = chunk.prefix(while: { $0 != ">" })
            #expect(element.contains("fill=\"none\""), "painting <text> in .both: \(element)")
        }
        #expect(page.contains("Outline Test"))
    }

    /// Consumers get font-independent output without asking for it. This is the whole point
    /// of the default: the failure mode it avoids is silent, so anyone who would have needed
    /// to opt in is exactly the person who would not have known to.
    @Test func outlinesAreTheDefault() throws {
        #expect(SVGRenderConfig().textRendering == .outlines)
        let page = try #require(try SVGRenderer()
            .render(CeolKitParser().parse(sampleABC, options: .default).score).first)
        #expect(page.contains("<use "))
        #expect(!page.contains("@font-face"))
        #expect(!page.contains("<text"))
    }

    /// `.fontFace` remains available and unchanged for hosts that want selectable text and
    /// control their own font environment.
    @Test func fontFaceModeIsStillAvailableAndUnchanged() throws {
        let page = try #require(try render(.fontFace).first)
        #expect(page.contains("<text "))
        #expect(page.contains("@font-face"))
        #expect(!page.contains("<use "))
        // The xlink namespace is declared only when something references a glyph, so
        // `.fontFace` documents are byte-for-byte what they were before outlines existed.
        #expect(!page.contains("xmlns:xlink"))
    }

    /// A centred run has to be measured from the font's advance widths before it can be
    /// placed, since there is no `text-anchor` to defer to once it is geometry.
    @Test func anchoredRunsArePositionedFromAdvanceWidths() throws {
        let outlined = try #require(try render(.outlines).first)
        let centre = SVGRenderConfig().pageSize.width / 2

        // The title is centred on the page, so its first glyph starts well to the left of
        // the centre line and the run as a whole straddles it.
        let titleGlyphs = outlined
            .components(separatedBy: "<use ")
            .dropFirst()
            .compactMap { chunk -> Double? in
                guard let range = chunk.range(of: "translate(") else { return nil }
                let rest = chunk[range.upperBound...].prefix(while: { $0 != " " })
                return Double(rest)
            }
        let title = try #require(titleGlyphs.first)
        #expect(title < centre - 20, "centred title run was not shifted left of centre")
        #expect(title > centre - 200)
    }

    /// Scale factors are ratios like 24/1000. Emitting them at the three-decimal precision
    /// used for page coordinates would round 0.0204 to 0.020 — a 2% size error on every
    /// glyph on the page.
    @Test func glyphScaleFactorsKeepEnoughPrecision() throws {
        let page = try #require(try render(.outlines, abc: sampleABC.replacing(
            "X:1", with: "%%ceolkit:scale 0.85\nX:1")).first)
        let scales = page
            .components(separatedBy: "scale(")
            .dropFirst()
            .compactMap { Double($0.prefix(while: { $0 != " " })) }
        #expect(!scales.isEmpty)
        // Three decimals could not represent a value this fine; six can.
        #expect(scales.contains { $0 != (($0 * 1000).rounded() / 1000) })
    }
}
