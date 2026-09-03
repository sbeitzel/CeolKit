import Foundation

/// One piece of a `%%footer` template once the `${…}` marks have been read out of it.
enum FooterSegment: Equatable, Sendable {
    /// Text CeolKit engraves and owns.
    case literal(String)
    /// A span the author marked `${name}` for a downstream consumer to replace, carrying the
    /// text CeolKit draws where nobody does.
    case tag(name: String, text: String)

    var text: String {
        switch self {
        case .literal(let text):  return text
        case .tag(_, let text):   return text
        }
    }

    /// The mark's name, or `nil` on a literal.
    var tagName: String? {
        if case .tag(let name, _) = self { return name }
        return nil
    }
}

/// What a footer template's placeholders resolve to on one page.
struct FooterContext: Sendable {
    let pageNumber: Int
    let pageCount: Int
    let title: String
    let date: String

    /// The value CeolKit draws into `${name}` where no consumer replaces it.
    ///
    /// A name CeolKit knows nothing about — a binder title, a section name — resolves to the
    /// empty string.  The mark still reaches the SVG as a positioned but empty group, which
    /// is exactly what a consumer meaning to stamp its own text there wants: CeolKit has no
    /// value for it and should not invent one.
    func value(forTag name: String) -> String {
        switch name.lowercased() {
        case "pagenumber": return String(pageNumber)
        case "pagecount":  return String(pageCount)
        case "title":      return title
        case "date":       return date
        default:           return ""
        }
    }
}

/// Reads a `%%footer` template into the spans that make it up (issue #137).
///
/// `${name}` marks a span as *consumer-substitutable*: CeolKit still draws its own value
/// there, but the renderer emits that span as one findable, self-describing element instead
/// of as loose glyphs, so a tool assembling pages from several separately-rendered files can
/// replace it without owning the font.  Everything else in the template is ordinary text.
enum FooterTemplate {
    /// A mark's name is an identifier, so that a `${` appearing in ordinary footer text
    /// cannot be mistaken for one.  Anything that does not parse as a mark — an unclosed
    /// brace, a name starting with a digit — stays in the literal text exactly as written,
    /// which is what an author who did not mean a mark expects to see engraved.
    ///
    /// Computed rather than stored: a `Regex` is not `Sendable`, so a `static let` holding
    /// one is a mutable global the concurrency checker rejects.
    private static var mark: Regex<(Substring, Substring)> { /\$\{([A-Za-z][A-Za-z0-9_.-]*)\}/ }

    /// Splits `template` into literal and marked spans, with every `$P`/`$T`/`$D`/`$d` in the
    /// literals resolved and `\t` unescaped.
    ///
    /// Marks are read out of the *raw* template, before the other placeholders expand, so a
    /// tune whose title happens to contain `${…}` cannot conjure a substitution point.
    static func segments(of template: String, context: FooterContext) -> [FooterSegment] {
        var segments: [FooterSegment] = []
        var cursor = template.startIndex
        for match in template.matches(of: mark) {
            if cursor < match.range.lowerBound {
                segments.append(.literal(expand(String(template[cursor..<match.range.lowerBound]),
                                                context)))
            }
            let name = String(match.1)
            segments.append(.tag(name: name, text: context.value(forTag: name)))
            cursor = match.range.upperBound
        }
        if cursor < template.endIndex {
            segments.append(.literal(expand(String(template[cursor...]), context)))
        }
        return segments
    }

    /// Splits `segments` at tab characters into the footer's columns — one, two, or three,
    /// as `buildFooterRows` has always read a template.  A mark never spans a tab, so it
    /// always belongs wholly to one column.
    static func columns(_ segments: [FooterSegment]) -> [[FooterSegment]] {
        var columns: [[FooterSegment]] = [[]]
        for segment in segments {
            guard case .literal(let text) = segment else {
                columns[columns.count - 1].append(segment)
                continue
            }
            for (index, piece) in text.components(separatedBy: "\t").enumerated() {
                if index > 0 { columns.append([]) }
                if !piece.isEmpty { columns[columns.count - 1].append(.literal(piece)) }
            }
        }
        return columns
    }

    /// Strips the whitespace a column is padded with, the way trimming the whole column
    /// string used to.  Only the literal ends are touched: a mark's default value is a value,
    /// not padding, and a consumer comparing what it reads against what it stamps should not
    /// have to know that CeolKit trimmed it.
    static func trimmed(_ column: [FooterSegment]) -> [FooterSegment] {
        var column = column
        if case .literal(let text)? = column.first {
            var trimmed = text
            while let first = trimmed.first, first.isWhitespace { trimmed.removeFirst() }
            column[0] = .literal(trimmed)
        }
        if case .literal(let text)? = column.last {
            var trimmed = text
            while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
            column[column.count - 1] = .literal(trimmed)
        }
        return column.filter { $0.tagName != nil || !$0.text.isEmpty }
    }

    private static func expand(_ text: String, _ context: FooterContext) -> String {
        text.replacing(/\$P/, with: String(context.pageNumber))
            .replacing(/\$T/, with: context.title)
            .replacing(/\$D/, with: context.date)
            .replacing(/\$d/, with: context.date)
            .replacing(/\\t/, with: "\t")
    }
}
