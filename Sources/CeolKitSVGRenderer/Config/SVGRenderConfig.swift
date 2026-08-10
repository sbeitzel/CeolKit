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
    /// How far a system may overrun the line, as a fraction of the line width, before the
    /// line breaker splits it.  Within this the system stays whole and the justifier
    /// compresses it instead, which is what an engraver does with a line that misses by a
    /// percent or two.
    public var lineOverflowTolerance: Double
    /// The most the justifier will stretch a system the line breaker created by splitting an
    /// over-long stave, as a multiple of its natural width.  Past this the system is left
    /// short rather than smeared across the page.  Systems the source broke are not capped.
    /// Generous by design — see ``Justifier/maxStretch``.
    public var maxSystemStretch: Double

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
        textRendering: TextRendering = .outlines,
        lineOverflowTolerance: Double = 0.02,
        maxSystemStretch: Double = 3.0
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
        self.lineOverflowTolerance = lineOverflowTolerance
        self.maxSystemStretch = maxSystemStretch
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
/// Defaults to ``outlines``, because embedding the faces is self-contained *for browsers
/// only*: no non-browser SVG rasteriser honours `@font-face`. resvg, librsvg, CairoSVG,
/// Skia, QtSvg, Inkscape and CoreGraphics all resolve `font-family` through a host font
/// database that the document cannot populate, so a score rendered by any of them shows
/// staff lines and stems but no noteheads, clefs, or rests unless the host installed the
/// faces out-of-band — a silent, plausible-looking failure rather than an error. Even
/// where the host did install them, the installed faces and the embedded ones can drift,
/// so the same document rasterises differently on two machines.
///
/// Emitting outlines moves that geometry into the document, which is the only way the same
/// score rasterises identically on macOS and in a Linux container.
public enum TextRendering: String, Sendable, CaseIterable {
    /// `<text>` elements plus the bundled faces as base64 `@font-face` sources.
    /// Text stays selectable and searchable; correct rendering needs a browser, or a host
    /// that has installed the faces itself (see ``CeolKitFonts``).
    case fontFace
    /// `<path>` outlines only, and no `@font-face` block. The default: renders identically
    /// everywhere and drops the embedded faces, at the cost of text that is no longer
    /// selectable or searchable — use ``both`` where that matters.
    case outlines
    /// Outlines for the geometry, plus non-painting `<text>` elements carrying the same
    /// strings so the document stays selectable, searchable, and accessible. Renders like
    /// ``outlines`` everywhere, but keeps the embedded faces and so the document size that
    /// goes with them.
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
