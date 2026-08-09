import Foundation

public struct SVGRenderConfig: Sendable {
    public var pageSize: PageSize
    public var margins: EdgeInsets
    public var staffSize: Double
    /// Vertical gap added between systems within a single tune.
    public var systemGap: Double
    /// Vertical gap added after the last system of a tune, before the next tune's title block.
    public var tuneGap: Double
    public var justifyLastSystem: Bool
    public var straightFlags: Bool
    public var graceSlurs: Bool
    /// Step between adjacent grace noteheads within one grace group, as a multiple of the
    /// grace notehead width.
    ///
    /// The notes of a beamed embellishment (a grip, taorluath or birl) share a beam and are
    /// engraved nearly adjacent, so this stays close to `1.0`.  It does not affect the padding
    /// at the outer edges of the group, nor the gap before the principal note.
    public var graceNoteSpacing: Double
    /// How glyphs reach the page: as `<text>` resolved through a font, or as geometry.
    public var textRendering: TextRendering

    public init(
        pageSize: PageSize = .letter,
        margins: EdgeInsets = EdgeInsets(top: 36, bottom: 36, left: 36, right: 36),
        staffSize: Double = 6.0,
        systemGap: Double? = nil,
        tuneGap: Double? = nil,
        justifyLastSystem: Bool = false,
        straightFlags: Bool = false,
        graceSlurs: Bool = true,
        graceNoteSpacing: Double = 1.05,
        textRendering: TextRendering = .fontFace
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.staffSize = staffSize
        self.systemGap = systemGap ?? staffSize * 4
        self.tuneGap = tuneGap ?? staffSize * 16
        self.justifyLastSystem = justifyLastSystem
        self.straightFlags = straightFlags
        self.graceSlurs = graceSlurs
        self.graceNoteSpacing = graceNoteSpacing
        self.textRendering = textRendering
    }

    /// Returns a copy with `staffSize` and the vertical gaps derived from it multiplied
    /// by `factor` (`%%ceolkit:scale`).  Page size and margins are absolute and unchanged:
    /// scaling the music must not resize the page.
    public func scaled(by factor: Double) -> SVGRenderConfig {
        guard factor != 1.0 else { return self }
        var copy = self
        copy.staffSize = staffSize * factor
        copy.systemGap = systemGap * factor
        copy.tuneGap = tuneGap * factor
        return copy
    }
}

/// How the emitter puts glyphs on the page.
///
/// The embedded-font default is self-contained *for browsers only*: no non-browser SVG
/// rasteriser honours `@font-face`. resvg, librsvg, CairoSVG, Skia, QtSvg, Inkscape and
/// CoreGraphics all resolve `font-family` through a host font database that the document
/// cannot populate, so a score rendered by any of them shows staff lines and stems but no
/// noteheads, clefs, or rests unless the host installed the faces out-of-band — a silent,
/// plausible-looking failure rather than an error.
///
/// Emitting outlines moves that geometry into the document, which is the only way the same
/// score rasterises identically on macOS and in a Linux container.
public enum TextRendering: String, Sendable, CaseIterable {
    /// `<text>` elements plus the bundled faces as base64 `@font-face` sources.
    /// Text stays selectable and searchable; correct rendering needs a browser, or a host
    /// that has installed the faces itself (see ``CeolKitFonts``).
    case fontFace
    /// `<path>` outlines only, and no `@font-face` block. Renders identically everywhere
    /// and drops the embedded faces, but the text is no longer selectable or searchable.
    case outlines
    /// Outlines for the geometry, plus non-painting `<text>` elements carrying the same
    /// strings so the document stays selectable, searchable, and accessible.
    case both

    /// Whether the document embeds the bundled faces as `@font-face` sources.
    public var embedsFontFaces: Bool { self != .outlines }

    /// Whether glyph geometry is written into the document as outlines.
    public var emitsOutlines: Bool { self != .fontFace }
}

public struct PageSize: Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let a4     = PageSize(width: 595.28, height: 841.89)
    public static let letter = PageSize(width: 612,    height: 792)
    public static let a3     = PageSize(width: 841.89, height: 1190.55)

    public var landscape: PageSize { PageSize(width: height, height: width) }
}

public struct EdgeInsets: Sendable {
    public var top, bottom, left, right: Double

    public init(top: Double, bottom: Double, left: Double, right: Double) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}
