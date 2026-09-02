/// The bundled faces as base64 `@font-face` sources.
///
/// Loaded only when the document actually embeds them: at roughly 1.5 MB of base64 for the
/// three faces, reading and encoding them for an outline-only document would be the most
/// expensive thing the emitter did, and all of it wasted.
struct EmbeddedFaces: Sendable {
    let bravura: String
    let libertinusSerif: String
    let libertinusSerifItalic: String
}

/// Lightweight SVG element builder used exclusively by `SVGEmitter`.
///
/// Accumulates element strings and wraps them in a complete SVG document via
/// `buildDocument(width:height:embeddedFaces:)`. Only the element types the
/// emitter needs are supported — this is not a general XML library.
///
/// When configured for outline rendering it also accumulates a glyph dictionary: each
/// distinct glyph is written once into `<defs>` and every occurrence becomes a `<use>`,
/// so a notehead drawn two hundred times on a page costs one outline.
struct SVGBuilder: Sendable {
    private(set) var elements: [String] = []

    let textRendering: TextRendering
    /// The parsed faces outlines are read from. `nil` leaves every run on `<text>`.
    let fonts: OutlineFontSet?

    /// Glyph outline path data by `<defs>` id; an empty string records a glyph that is
    /// known to have no outline (a space, say) so it is not decoded again.
    private var glyphPaths: [String: String] = [:]
    /// Ids of the non-empty glyphs, in the order they were first drawn, so that the
    /// emitted `<defs>` block is stable rather than dictionary-ordered.
    private var glyphOrder: [String] = []

    init(textRendering: TextRendering = .fontFace, fonts: OutlineFontSet? = nil) {
        self.textRendering = textRendering
        self.fonts = fonts
    }

    mutating func line(
        x1: Double, y1: Double, x2: Double, y2: Double,
        stroke: String = "black", strokeWidth: Double = 1.0
    ) {
        elements.append(
            "<line x1=\"\(fmt(x1))\" y1=\"\(fmt(y1))\" x2=\"\(fmt(x2))\" y2=\"\(fmt(y2))\"" +
            " stroke=\"\(esc(stroke))\" stroke-width=\"\(fmt(strokeWidth))\"/>"
        )
    }

    mutating func text(
        _ content: String,
        x: Double, y: Double,
        fontFamily: String,
        fontSize: Double,
        fill: String = "black",
        textAnchor: String = "start",
        fontStyle: String? = nil,
        className: String? = nil
    ) {
        if textRendering.emitsOutlines,
           let resolved = fonts?.resolve(family: fontFamily, italic: fontStyle == "italic") {
            appendOutlineRun(content, x: x, y: y,
                             face: resolved.key, font: resolved.font,
                             fontSize: fontSize, fill: fill,
                             textAnchor: textAnchor, className: className)
            guard textRendering == .both else { return }
            // A non-painting copy of the run, so the document stays selectable, searchable,
            // and legible to a screen reader even though the geometry comes from the paths.
            appendTextElement(content, x: x, y: y, fontFamily: fontFamily, fontSize: fontSize,
                              fill: "none", textAnchor: textAnchor, fontStyle: fontStyle,
                              className: className)
            return
        }
        // Reached in `.fontFace`, and for any family this renderer does not bundle. Losing
        // the content outright would be worse than emitting a run the host may not resolve.
        appendTextElement(content, x: x, y: y, fontFamily: fontFamily, fontSize: fontSize,
                          fill: fill, textAnchor: textAnchor, fontStyle: fontStyle,
                          className: className)
    }

    /// Draws `content` stretched independently in x and y — the shape a *stretchy* glyph
    /// needs, and the one a `font-size` cannot express.
    ///
    /// SMuFL designs the brace to be drawn at whatever height the staves it joins happen to
    /// span — three times its natural height over a piano system — while its arms thicken by
    /// nothing like as much.  So the two axes have to move independently: `fontSize` fixes
    /// the natural size on both, and `xScale`/`yScale` stretch from there, `1` leaving an
    /// axis alone.
    ///
    /// `x` and `y` are where the run's origin lands on the page; the stretch is applied
    /// about that point, so a glyph sitting on its baseline stays on it however far it is
    /// stretched.
    mutating func stretchedText(
        _ content: String,
        x: Double, y: Double,
        fontFamily: String,
        fontSize: Double,
        xScale: Double,
        yScale: Double,
        fill: String = "black",
        className: String? = nil
    ) {
        if textRendering.emitsOutlines,
           let resolved = fonts?.resolve(family: fontFamily, italic: false) {
            appendOutlineRun(content, x: x, y: y,
                             face: resolved.key, font: resolved.font,
                             fontSize: fontSize, fill: fill,
                             textAnchor: "start", className: className,
                             xScale: xScale, yScale: yScale)
            guard textRendering == .both else { return }
            appendStretchedTextElement(content, x: x, y: y, fontFamily: fontFamily,
                                       fontSize: fontSize, xScale: xScale, yScale: yScale,
                                       fill: "none", className: className)
            return
        }
        appendStretchedTextElement(content, x: x, y: y, fontFamily: fontFamily,
                                   fontSize: fontSize, xScale: xScale, yScale: yScale,
                                   fill: fill, className: className)
    }

    /// Wraps everything `body` draws in a `<g>` carrying `transform`.
    ///
    /// The one thing a group is needed for here is the stretch above: a `<text>` element
    /// carries a single `font-size`, so the only way to scale a run of text by different
    /// factors on the two axes is to put the factors on an element around it.  A group that
    /// wraps nothing is dropped rather than emitted empty.
    mutating func group(transform: String, _ body: (inout SVGBuilder) -> Void) {
        let start = elements.count
        body(&self)
        guard elements.count > start else { return }
        let inner = elements[start...].map { "  " + $0 }
        elements.replaceSubrange(start..., with:
            ["<g transform=\"\(esc(transform))\">"] + inner + ["</g>"])
    }

    mutating func path(
        d: String,
        fill: String? = nil,
        stroke: String? = nil,
        strokeWidth: Double? = nil
    ) {
        var attrs = "d=\"\(esc(d))\""
        if let f = fill   { attrs += " fill=\"\(esc(f))\"" }
        if let s = stroke { attrs += " stroke=\"\(esc(s))\"" }
        if let w = strokeWidth { attrs += " stroke-width=\"\(fmt(w))\"" }
        elements.append("<path \(attrs)/>")
    }

    mutating func comment(_ text: String) {
        elements.append("<!-- \(text) -->")
    }

    mutating func rect(
        x: Double, y: Double, width: Double, height: Double,
        fill: String = "none",
        stroke: String? = nil,
        strokeWidth: Double? = nil
    ) {
        var attrs = "x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(width))\" height=\"\(fmt(height))\""
        attrs += " fill=\"\(esc(fill))\""
        if let s = stroke { attrs += " stroke=\"\(esc(s))\"" }
        if let w = strokeWidth { attrs += " stroke-width=\"\(fmt(w))\"" }
        elements.append("<rect \(attrs)/>")
    }

    func buildDocument(width: Double, height: Double,
                       embeddedFaces: EmbeddedFaces?) -> String {
        var defs: [String] = []
        if let faces = embeddedFaces {
            defs.append("    <style>")
            defs += fontFaceRule(family: "Bravura", italic: false, base64: faces.bravura)
            defs += fontFaceRule(family: "Libertinus Serif", italic: false,
                                 base64: faces.libertinusSerif)
            defs += fontFaceRule(family: "Libertinus Serif", italic: true,
                                 base64: faces.libertinusSerifItalic)
            defs.append("    </style>")
        }
        for id in glyphOrder {
            defs.append("    <path id=\"\(id)\" d=\"\(glyphPaths[id] ?? "")\"/>")
        }

        // The xlink namespace is declared only when glyphs are drawn, because only `<use>`
        // needs it: the elements carry both the SVG 2 `href` and the SVG 1.1 `xlink:href`,
        // rasterisers being split on which they honour, and an undeclared prefix would make
        // the document ill-formed XML.
        let xlink = glyphOrder.isEmpty ? "" : " xmlns:xlink=\"http://www.w3.org/1999/xlink\""
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\"\(xlink)" +
                     " viewBox=\"0 0 \(fmt(width)) \(fmt(height))\"" +
                     " width=\"\(fmt(width))\" height=\"\(fmt(height))\">"]
        if !defs.isEmpty {
            lines.append("  <defs>")
            lines += defs
            lines.append("  </defs>")
        }
        lines += elements.map { "  " + $0 }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }

    private func fontFaceRule(family: String, italic: Bool, base64: String) -> [String] {
        var rule = ["      @font-face {", "        font-family: \"\(family)\";"]
        if italic { rule.append("        font-style: italic;") }
        rule.append("        src: url('data:font/otf;base64,\(base64)') format('opentype');")
        rule.append("      }")
        return rule
    }

    // MARK: - Text

    private mutating func appendTextElement(
        _ content: String, x: Double, y: Double,
        fontFamily: String, fontSize: Double, fill: String,
        textAnchor: String, fontStyle: String?, className: String?
    ) {
        var attrs = "x=\"\(fmt(x))\" y=\"\(fmt(y))\""
        attrs += " font-family=\"\(esc(fontFamily))\" font-size=\"\(fmt(fontSize))\""
        attrs += " fill=\"\(esc(fill))\""
        if textAnchor != "start"  { attrs += " text-anchor=\"\(esc(textAnchor))\"" }
        if let style = fontStyle  { attrs += " font-style=\"\(esc(style))\"" }
        if let cls   = className  { attrs += " class=\"\(esc(cls))\"" }
        elements.append("<text \(attrs)>\(esc(content))</text>")
    }

    /// The `<text>` route for `stretchedText`: the run drawn at the origin of a group that
    /// carries the placement and the stretch.  Identity factors would produce the element
    /// `appendTextElement` writes on its own, wrapped in a group that does nothing, so they
    /// take that path instead and the ordinary output is untouched.
    private mutating func appendStretchedTextElement(
        _ content: String, x: Double, y: Double,
        fontFamily: String, fontSize: Double,
        xScale: Double, yScale: Double,
        fill: String, className: String?
    ) {
        guard xScale != 1 || yScale != 1 else {
            appendTextElement(content, x: x, y: y, fontFamily: fontFamily, fontSize: fontSize,
                              fill: fill, textAnchor: "start", fontStyle: nil,
                              className: className)
            return
        }
        let transform = "translate(\(fmt(x)) \(fmt(y))) " +
                        "scale(\(fmtScale(xScale)) \(fmtScale(yScale)))"
        group(transform: transform) {
            $0.appendTextElement(content, x: 0, y: 0, fontFamily: fontFamily,
                                 fontSize: fontSize, fill: fill, textAnchor: "start",
                                 fontStyle: nil, className: className)
        }
    }

    /// Lays out `content` one glyph per Unicode scalar and emits a `<use>` per glyph.
    ///
    /// There is no shaping, kerning, or ligature substitution here. That is not a shortcut
    /// taken against the `<text>` path this replaces — a rasteriser handed the same string
    /// and these faces applies no `GPOS`/`GSUB` either unless it runs a full shaper, so
    /// nominal advances are what the font-face route was already producing.
    private mutating func appendOutlineRun(
        _ content: String, x: Double, y: Double,
        face: OutlineFontSet.FaceKey, font: OpenTypeFont,
        fontSize: Double, fill: String, textAnchor: String, className: String?,
        xScale: Double = 1, yScale: Double = 1
    ) {
        let scale = fontSize / font.unitsPerEm
        // A `<use>` already carries a transform of its own, so an anisotropic stretch costs
        // nothing here beyond the two factors: no wrapping group, and the same `<defs>`
        // entry the glyph has at its natural size.
        let (scaleX, scaleY) = (scale * xScale, scale * yScale)
        // An unencoded scalar falls back to glyph 0, whose .notdef box is what a rasteriser
        // would have drawn: a visible gap beats a run that silently shortens.
        let glyphs = content.unicodeScalars.map { font.glyphID(for: $0) ?? 0 }
        guard !glyphs.isEmpty else { return }

        var penX = x
        switch textAnchor {
        case "middle":
            penX -= glyphs.reduce(0) { $0 + font.advance(forGlyph: $1) } * scaleX / 2
        case "end":
            penX -= glyphs.reduce(0) { $0 + font.advance(forGlyph: $1) } * scaleX
        default:
            break
        }

        for glyph in glyphs {
            if let id = registerGlyph(face: face, glyph: glyph, font: font) {
                var attrs = "href=\"#\(id)\" xlink:href=\"#\(id)\""
                attrs += " transform=\"translate(\(fmt(penX)) \(fmt(y)))"
                attrs += " scale(\(fmtScale(scaleX)) \(fmtScale(-scaleY)))\""
                if fill != "black" { attrs += " fill=\"\(esc(fill))\"" }
                if let cls = className { attrs += " class=\"\(esc(cls))\"" }
                elements.append("<use \(attrs)/>")
            }
            penX += font.advance(forGlyph: glyph) * scaleX
        }
    }

    /// Ensures `glyph` has a `<defs>` entry and returns its id, or `nil` when the glyph has
    /// no outline to draw — a space, or one whose charstring the interpreter could not read.
    private mutating func registerGlyph(face: OutlineFontSet.FaceKey, glyph: Int,
                                        font: OpenTypeFont) -> String? {
        let id = "\(face.rawValue)-g\(glyph)"
        if let existing = glyphPaths[id] {
            return existing.isEmpty ? nil : id
        }
        let pathData = ((try? font.outline(forGlyph: glyph)) ?? GlyphPath()).pathData
        glyphPaths[id] = pathData
        guard !pathData.isEmpty else { return nil }
        glyphOrder.append(id)
        return id
    }

    // MARK: - Helpers

    func fmt(_ v: Double) -> String {
        trimmed(String(format: "%.3f", v))
    }

    /// Glyph scale factors are ratios like `24/1000`, so page-coordinate precision would
    /// quantise them to whole percents — a 2% size error on every glyph. Six decimals keeps
    /// the error below a millionth of an em.
    func fmtScale(_ v: Double) -> String {
        trimmed(String(format: "%.6f", v))
    }

    private func trimmed(_ formatted: String) -> String {
        var s = formatted
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    func esc(_ s: String) -> String {
        s.replacing("&", with: "&amp;")
         .replacing("<", with: "&lt;")
         .replacing(">", with: "&gt;")
         .replacing("\"", with: "&quot;")
    }
}
