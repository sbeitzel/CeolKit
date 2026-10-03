import CeolKitModel
import Foundation

public struct SVGRenderConfig: Sendable {
    public var pageSize: PageSize
    public var margins: EdgeInsets
    /// The staff space at a page scale of 1 — abcm2ps's `%%scale 1`.  What is drawn is this
    /// times ``scale``; see ``scaled(by:)``.
    public var staffSize: Double
    /// The page scale, as abcm2ps's `%%scale` value (issue #203), before the document says
    /// anything: what abcm2ps's `-s` flag sets.  A `%%scale`, `%%pagescale` or
    /// `%%ceolkit:scale` in the document overrides it.
    ///
    /// Defaults to abcm2ps's own `0.75` (`%%pagescale 1`), so a document comes out the size
    /// abcm2ps prints it.  It scales the music, the title block, the words and every other
    /// piece of text the tune sets; not the page, its margins or the footer.
    public var scale: Double
    /// Vertical gap added between systems within a single tune.
    public var systemGap: Double
    /// Vertical gap added between two staves of one system that no brace or bracket joins
    /// — the staff group a multi-voice tune draws for each source line.
    ///
    /// Deliberately smaller than ``systemGap``: the staves of a system are read together,
    /// so they have to sit closer to each other than the system does to its neighbours,
    /// or the group stops reading as a unit.  Only tunes with more than one voice use it.
    public var staffGap: Double
    /// Vertical gap added between two staves whose innermost brace or bracket is the same
    /// one — the staves of a single part.
    ///
    /// Smaller again than ``staffGap``, and for the same reason one step further in: staves
    /// under one span are read as a unit, and the spacing has to say so on its own.
    /// `[{A B} C]` should read as "A and B belong together, C is alongside" without the
    /// reader having to trace the brace to find out — so A–B is spaced with this and B–C,
    /// which meets only at the bracket outside them both, with ``staffGap``.  See
    /// ``BracketColumns/sharesInnermostSpan(_:_:)``.  A system with no plan has no spans at
    /// all, so every boundary in it uses ``staffGap`` and the page is the one the renderer
    /// drew before spans existed.
    public var spanStaffGap: Double
    /// Vertical gap added after the last system of a tune, before the next tune's title block.
    public var tuneGap: Double
    /// abcm2ps's `%%stretchlast`, from 0 to 1: the last system of a tune is stretched to the
    /// full line when its natural width reaches `1 − stretchLast` of it (issue #198).  The
    /// default, `0.25`, is abcm2ps's.  `0` leaves every last system at its natural width; `1`
    /// stretches every one.  A `%%stretchlast` in the document overrides it.
    public var stretchLast: Double
    /// abcm2ps's `%%stretchstaff`: whether systems are stretched to the line at all.  `false`
    /// draws every system at its natural width, the last one included; a system that
    /// overruns is still compressed to fit.  A `%%stretchstaff` in the document overrides it.
    public var stretchStaff: Bool
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
    /// Faces the host supplies, tried before any other when text names a font (issue #190).
    /// `nil` — the default — leaves the system's fonts, if enabled, and the bundled faces.
    public var fontLibrary: FontLibrary?
    /// Whether a font named by the document may be looked up among the fonts installed on
    /// the machine: through CoreText on Apple platforms, and on Linux through fontconfig,
    /// where `libfontconfig.so.1` is installed (it is loaded at run time, never linked).
    /// Elsewhere it finds nothing.  Off by default, because it makes the output
    /// depend on the machine it is rendered on; the SVG that results is still portable in
    /// ``TextRendering/outlines`` mode, which carries the glyphs with it.
    public var systemFonts: Bool
    /// A house style: the font for each kind of text, before the document says anything
    /// (issue #186).  Laid over CeolKit's own defaults and under the document's font
    /// directives (§11.4.2) — a `%%composerfont` in the ABC still wins — so a host can, say,
    /// set every composer line in Zapf Chancery and leave everything else as it is.  Each
    /// spec's `nil` half keeps the default's.
    public var textFonts: [TextFontRole: FontSpec]

    public init(
        pageSize: PageSize = .letter,
        margins: EdgeInsets = EdgeInsets(top: 36, bottom: 36, left: 36, right: 36),
        staffSize: Double = 6.0,
        scale: Double = 0.75,
        systemGap: Double? = nil,
        staffGap: Double? = nil,
        spanStaffGap: Double? = nil,
        tuneGap: Double? = nil,
        stretchLast: Double = 0.25,
        stretchStaff: Bool = true,
        straightFlags: Bool = false,
        graceSlurs: Bool = true,
        graceNoteSpacing: Double = 1.05,
        textRendering: TextRendering = .outlines,
        lineOverflowTolerance: Double = 0.02,
        maxSystemStretch: Double = 3.0,
        fontLibrary: FontLibrary? = nil,
        systemFonts: Bool = false,
        textFonts: [TextFontRole: FontSpec] = [:]
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.staffSize = staffSize
        self.scale = scale
        self.systemGap = systemGap ?? staffSize * 4
        self.staffGap = staffGap ?? staffSize * 3
        self.spanStaffGap = spanStaffGap ?? staffSize * 2
        self.tuneGap = tuneGap ?? staffSize * 16
        self.stretchLast = min(max(stretchLast, 0), 1)
        self.stretchStaff = stretchStaff
        self.straightFlags = straightFlags
        self.graceSlurs = graceSlurs
        self.graceNoteSpacing = graceNoteSpacing
        self.textRendering = textRendering
        self.lineOverflowTolerance = lineOverflowTolerance
        self.maxSystemStretch = maxSystemStretch
        self.fontLibrary = fontLibrary
        self.systemFonts = systemFonts
        self.textFonts = textFonts
    }

    /// The staff space as drawn where the document sets no page scale of its own:
    /// ``staffSize`` at ``scale``.  4.5 points at the defaults, as abcm2ps draws it.
    public var scaledStaffSize: Double { staffSize * scale }

    /// Returns a copy with `staffSize` and the vertical gaps derived from it multiplied
    /// by `factor` — the page scale, ``scale`` or the document's `%%scale`.  Page size and
    /// margins are absolute and unchanged: scaling the music must not resize the page.
    public func scaled(by factor: Double) -> SVGRenderConfig {
        guard factor != 1.0 else { return self }
        var copy = self
        copy.staffSize = staffSize * factor
        copy.systemGap = systemGap * factor
        copy.staffGap = staffGap * factor
        copy.spanStaffGap = spanStaffGap * factor
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
