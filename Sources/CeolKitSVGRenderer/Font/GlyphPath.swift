/// A glyph outline expressed in the font's own design units, y-up.
///
/// Outlines are stored untransformed so that one definition can serve every size and
/// position the glyph is drawn at: the emitter writes each distinct glyph once into
/// `<defs>` and positions every occurrence with a `<use>` transform. A notehead that
/// appears two hundred times on a page therefore costs one outline.
///
/// Font units are integral in both bundled faces, so the emitted path data is compact
/// and loses nothing to rounding — all the size-dependent arithmetic happens in the
/// `<use>` transform instead.
struct GlyphPath: Sendable, Equatable {

    struct Point: Sendable, Equatable {
        var x: Double
        var y: Double
    }

    enum Segment: Sendable, Equatable {
        case move(to: Point)
        case line(to: Point)
        case curve(control1: Point, control2: Point, to: Point)
        /// A quadratic Bézier, as TrueType (`glyf`) outlines are drawn.  Kept quadratic
        /// rather than raised to a cubic: SVG draws it as it stands, in less path data.
        case quadCurve(control: Point, to: Point)
        case close
    }

    var segments: [Segment] = []

    var isEmpty: Bool { segments.isEmpty }

    /// The outline under the affine map `x' = a·x + c·y + dx`, `y' = b·x + d·y + dy` — how a
    /// TrueType composite places a component.  An affine map takes a Bézier's control points
    /// to the transformed curve's, so every segment keeps its kind.
    func transformed(a: Double, b: Double, c: Double, d: Double,
                     dx: Double, dy: Double) -> GlyphPath {
        func map(_ p: Point) -> Point {
            Point(x: a * p.x + c * p.y + dx, y: b * p.x + d * p.y + dy)
        }
        return GlyphPath(segments: segments.map { segment in
            switch segment {
            case .move(let p):                return .move(to: map(p))
            case .line(let p):                return .line(to: map(p))
            case .curve(let c1, let c2, let p): return .curve(control1: map(c1), control2: map(c2),
                                                              to: map(p))
            case .quadCurve(let c, let p):    return .quadCurve(control: map(c), to: map(p))
            case .close:                      return .close
            }
        })
    }

    /// The outline as an SVG `d` attribute, in font units and the font's y-up orientation.
    ///
    /// Emitted with absolute commands: the saving from relative encoding is small next to
    /// the base64 font payload this replaces, and absolute data is far easier to check by
    /// eye against a glyph's bounding box when a placement looks wrong.
    var pathData: String {
        var out = ""
        out.reserveCapacity(segments.count * 12)
        for segment in segments {
            switch segment {
            case .move(let p):
                out += "M\(fmt(p.x)) \(fmt(p.y))"
            case .line(let p):
                out += "L\(fmt(p.x)) \(fmt(p.y))"
            case .curve(let c1, let c2, let end):
                out += "C\(fmt(c1.x)) \(fmt(c1.y)) \(fmt(c2.x)) \(fmt(c2.y)) \(fmt(end.x)) \(fmt(end.y))"
            case .quadCurve(let c, let end):
                out += "Q\(fmt(c.x)) \(fmt(c.y)) \(fmt(end.x)) \(fmt(end.y))"
            case .close:
                out += "Z"
            }
        }
        return out
    }

    /// Formats a font-unit coordinate as compactly as it can be written exactly.
    ///
    /// Type 2 charstrings carry integers almost exclusively, but the format also permits
    /// 16.16 fixed-point operands — and a TrueType outline's implied on-curve points fall on
    /// half units, its scaled composites anywhere — so fractional values are kept to three
    /// decimals: a thousandth of a font unit, i.e. a millionth of an em.
    private func fmt(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var s = String(format: "%.3f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
