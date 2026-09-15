import Foundation

/// A run of text drawn as glyph outlines, with the metrics a caller needs to place it.
///
/// Produced by ``TextOutliner/outline(_:face:fontSize:fill:)``. Every measure is in the
/// same page units as `fontSize`.
public struct OutlinedText: Sendable, Equatable {
    /// SVG markup drawing the run with its pen origin at (0, 0) on the baseline, y down.
    ///
    /// A single `<g>` carrying the fill, holding one `<path>` per inked glyph. The fragment
    /// is self-contained — no `id`s, no `<use>`, no `<defs>`, no namespace prefixes — so it
    /// can be dropped into any SVG document, as many times as needed, and positioned by
    /// wrapping it in a `<g transform="…">`. Empty when the run has nothing to ink, such as
    /// an empty or all-space string.
    public let svg: String
    /// The sum of the glyphs' nominal advances: the measure CeolKit lays text out with.
    public let advanceWidth: Double
    /// The face's typographic ascender at this size: how far above the baseline it reaches.
    public let ascent: Double
    /// The face's typographic descender at this size, as a positive distance below the
    /// baseline — the same sign convention as ``LibertinusSerifMetrics/descenderRatio``.
    public let descent: Double
}

/// Outlines text in a bundled face without going through the parser or a `Score` (#146).
///
/// For a page with text and no music that still has to render without a font environment
/// — a divider page rasterised by `rsvg-convert` alongside CeolKit's tune pages, say.
///
/// Layout is exactly what the engraver uses for ``TextRendering/outlines``: one glyph per
/// Unicode scalar at its nominal advance, with `.notdef` drawn for a scalar the face does
/// not encode. There is no shaping, kerning or ligature substitution, so a string measured
/// here and a string engraved in a tune are the same width.
public enum TextOutliner {

    /// Outlines `text` in `face` at `fontSize`.
    ///
    /// - Parameters:
    ///   - text: The run to draw. Line breaks are not interpreted; lay out one line per call.
    ///   - face: The bundled face to draw it in.
    ///   - fontSize: The em size, in page units. Expected to be positive.
    ///   - fill: The SVG paint the glyphs are filled with.
    /// - Throws: ``CeolKitFontsError/resourceNotFound(_:)`` if `face` is missing from the
    ///   bundle, or ``CeolKitFontsError/unreadable(_:)`` if it cannot be parsed.
    public static func outline(
        _ text: String,
        face: CeolKitFonts.Face,
        fontSize: Double,
        fill: String = "black"
    ) throws -> OutlinedText {
        let font = try OutlineFontSet.font(for: face)
        let scale = fontSize / font.unitsPerEm
        let run = OutlineRun(text, font: font)

        var pathData: [Int: String] = [:]
        var paths: [String] = []
        for (glyph, penX) in run.placements(startX: 0, scaleX: scale) {
            let d = pathData[glyph] ?? ((try? font.outline(forGlyph: glyph)) ?? GlyphPath()).pathData
            pathData[glyph] = d
            guard !d.isEmpty else { continue }
            paths.append("<path d=\"\(d)\" transform=\"translate(\(SVGFormat.coordinate(penX)) 0)" +
                         " scale(\(SVGFormat.scale(scale)) \(SVGFormat.scale(-scale)))\"/>")
        }

        let svg = paths.isEmpty ? "" :
            (["<g fill=\"\(SVGFormat.escape(fill))\">"] + paths.map { "  " + $0 } + ["</g>"])
                .joined(separator: "\n")
        return OutlinedText(
            svg: svg,
            advanceWidth: font.width(of: text, fontSize: fontSize),
            ascent: font.ascender * scale,
            descent: -font.descender * scale)
    }

    /// How wide `text` is drawn in `face` at `fontSize` — the ``OutlinedText/advanceWidth``
    /// that ``outline(_:face:fontSize:fill:)`` would report, without decoding any outlines.
    ///
    /// For fitting text to a width before outlining it.
    ///
    /// - Throws: As ``outline(_:face:fontSize:fill:)``.
    public static func width(of text: String, face: CeolKitFonts.Face, fontSize: Double) throws -> Double {
        try OutlineFontSet.font(for: face).width(of: text, fontSize: fontSize)
    }
}
