import Foundation

/// Typographic metrics for Libertinus Serif Regular v7.040,
/// extracted from the font's OS/2 and head OpenType tables.
///
/// All ratios are expressed as a fraction of the em-square (unitsPerEm = 1000).
/// Multiply by `fontSize` to get point values at any given size.
public struct LibertinusSerifMetrics: Sendable {

    /// The deepest extent of descenders below the baseline, as a fraction of the em.
    /// Derived from OS/2 sTypoDescender (−246 / 1000).
    public static let descenderRatio: Double = 246.0 / 1000.0  // 0.246

    /// The highest extent of ascenders above the baseline, as a fraction of the em.
    /// Derived from OS/2 sTypoAscender (894 / 1000).
    public static let ascenderRatio: Double = 894.0 / 1000.0   // 0.894

    /// Height of capital letters above the baseline, as a fraction of the em.
    /// Regular: OS/2 sCapHeight 658 / 1000. Italic: 645 / 1000.
    public static let capHeightRatio: Double = 658.0 / 1000.0        // 0.658 (regular)
    public static let italicCapHeightRatio: Double = 645.0 / 1000.0  // 0.645 (italic)

    /// Height of lower-case letters (e.g. 'x') above the baseline, as a fraction of the em.
    /// Derived from OS/2 sxHeight (429 / 1000).
    public static let xHeightRatio: Double = 429.0 / 1000.0    // 0.429

    /// Loads the Libertinus Serif Regular OTF from the module bundle and returns it
    /// as a base64-encoded string suitable for embedding in an SVG `@font-face` rule.
    public static func loadBase64() throws -> String {
        try loadFontBase64(resource: "LibertinusSerif-Regular")
    }

    /// Loads the Libertinus Serif Italic OTF from the module bundle and returns it
    /// as a base64-encoded string suitable for embedding in an SVG `@font-face` rule.
    public static func loadItalicBase64() throws -> String {
        try loadFontBase64(resource: "LibertinusSerif-Italic")
    }

    private static func loadFontBase64(resource: String) throws -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "otf") else {
            throw LibertinusSerifMetricsError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return data.base64EncodedString()
    }
}

enum LibertinusSerifMetricsError: Error {
    case resourceNotFound
}
