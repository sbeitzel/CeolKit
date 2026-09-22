//
//  SVGPrimitives.swift
//  CeolKitSVGGeometry
//
//  Minimal, attribute-order-independent reading of the drawing primitives the
//  SVG renderer emits.  Deliberately not a general SVG parser: it understands
//  only what `SVGEmitter` actually writes.
//

import Foundation

/// A `<line>` element from the emitted SVG.
struct SVGLine: Equatable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let strokeWidth: Double?

    var isHorizontal: Bool { y1 == y2 }
    var isVertical: Bool { x1 == x2 }
}

enum SVGPrimitives {

    /// Every `<line>` element in `svg`, in document order.
    ///
    /// Attributes are read by name rather than by position, so the emitter is free to
    /// reorder them without silently breaking geometry extraction.
    static func lines(in svg: String) -> [SVGLine] {
        svg.matches(of: #/<line\b([^>]*)>/#).compactMap { match in
            let attrs = attributes(String(match.1))
            guard let x1 = attrs["x1"], let y1 = attrs["y1"],
                  let x2 = attrs["x2"], let y2 = attrs["y2"]
            else { return nil }
            return SVGLine(x1: x1, y1: y1, x2: x2, y2: y2, strokeWidth: attrs["stroke-width"])
        }
    }

    /// The `width` and `height` of the root `<svg>` element.
    static func pageSize(in svg: String) throws -> (width: Double, height: Double) {
        guard let root = svg.firstMatch(of: #/<svg\b([^>]*)>/#) else {
            throw SVGGeometryError.missingRootElement
        }
        let attrs = String(root.1)
        guard let width = attrs.firstMatch(of: #/\bwidth="([^"]*)"/#).flatMap({ points(in: $0.1) }),
              let height = attrs.firstMatch(of: #/\bheight="([^"]*)"/#).flatMap({ points(in: $0.1) })
        else {
            throw SVGGeometryError.missingPageDimensions
        }
        return (width, height)
    }

    /// One root-element length, in points.
    ///
    /// Only the root carries units — the body's attributes are user units, and
    /// `attributes(_:)` reads them as they stand. A page written by this library says
    /// `792pt`, but a document from elsewhere may use any of SVG's absolute units, and an
    /// unqualified number is a user unit, which in a document whose `viewBox` matches its
    /// size in points is a point.
    private static func points<S: StringProtocol>(in text: S) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let unitStart = text.firstIndex { !($0.isNumber || $0 == "." || $0 == "-"
                                            || $0 == "+" || $0 == "e" || $0 == "E") }
            ?? text.endIndex
        guard let value = Double(text[..<unitStart]) else { return nil }
        switch text[unitStart...].lowercased() {
        case "", "pt": return value
        case "px":     return value * 72 / 96
        case "in":     return value * 72
        case "pc":     return value * 12
        case "cm":     return value * 72 / 2.54
        case "mm":     return value * 72 / 25.4
        default:       return nil
        }
    }

    /// Numeric attributes of one element, keyed by name.
    ///
    /// Non-numeric values (`stroke="black"`) are dropped: nothing here needs them, and
    /// keeping the dictionary homogeneous keeps the call sites free of casts.
    private static func attributes(_ attrs: String) -> [String: Double] {
        var result: [String: Double] = [:]
        // Names carry digits (`x1`, `y2`) and hyphens (`stroke-width`), but always open
        // with a letter.
        for pair in attrs.matches(of: #/([a-zA-Z][a-zA-Z0-9-]*)="([^"]*)"/#) {
            if let value = Double(pair.2) {
                result[String(pair.1)] = value
            }
        }
        return result
    }
}
