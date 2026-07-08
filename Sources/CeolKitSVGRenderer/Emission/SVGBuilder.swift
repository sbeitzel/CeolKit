/// Lightweight SVG element builder used exclusively by `SVGEmitter`.
///
/// Accumulates element strings and wraps them in a complete SVG document via
/// `buildDocument(width:height:bravuraBase64:)`. Only the element types the
/// emitter needs are supported — this is not a general XML library.
struct SVGBuilder: Sendable {
    private(set) var elements: [String] = []

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
        var attrs = "x=\"\(fmt(x))\" y=\"\(fmt(y))\""
        attrs += " font-family=\"\(esc(fontFamily))\" font-size=\"\(fmt(fontSize))\""
        attrs += " fill=\"\(esc(fill))\""
        if textAnchor != "start"  { attrs += " text-anchor=\"\(esc(textAnchor))\"" }
        if let style = fontStyle  { attrs += " font-style=\"\(esc(style))\"" }
        if let cls   = className  { attrs += " class=\"\(esc(cls))\"" }
        elements.append("<text \(attrs)>\(esc(content))</text>")
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
                       bravuraBase64: String,
                       libertinusSerifBase64: String,
                       libertinusSerifItalicBase64: String) -> String {
        let defs = """
          <defs>
            <style>
              @font-face {
                font-family: "Bravura";
                src: url('data:font/otf;base64,\(bravuraBase64)') format('opentype');
              }
              @font-face {
                font-family: "Libertinus Serif";
                src: url('data:font/otf;base64,\(libertinusSerifBase64)') format('opentype');
              }
              @font-face {
                font-family: "Libertinus Serif";
                font-style: italic;
                src: url('data:font/otf;base64,\(libertinusSerifItalicBase64)') format('opentype');
              }
            </style>
          </defs>
        """
        let body = elements.map { "  " + $0 }.joined(separator: "\n")
        let vb = "0 0 \(fmt(width)) \(fmt(height))"
        return """
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(vb)" width="\(fmt(width))" height="\(fmt(height))">
          \(defs)
          \(body)
          </svg>
          """
    }

    // MARK: - Helpers

    func fmt(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
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
