/// How heavy a face is asked to be.
///
/// Two weights, because the font names ABC uses (§11.4.2 asks for PostScript names) only
/// ever say "Bold" or nothing.  A face matches by `OS/2.usWeightClass`: 600 and above is bold.
public enum FontWeight: String, Sendable, Hashable, Codable, CaseIterable {
    case regular
    case bold
}

/// Whether a face is asked to slant.  Italic and oblique are one request: a font family has
/// one or the other, and `Helvetica-Oblique` is answered by whichever slanted face it has.
public enum FontStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case upright
    case italic
}

/// A face to draw text in, as a document or a host names it (issue #190).
///
/// Usually made from a PostScript name, which is what ABC's font directives carry
/// (`%%wordsfont Courier-Bold 16`): ``init(postScriptName:)`` splits it into a family, a
/// weight and a style.  The name itself is kept, because a face whose PostScript name is
/// exactly that is the best match there is.
public struct FontRequest: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The family asked for: "Times", "Courier New", or a generic family — `serif`,
    /// `sans-serif`, `monospace`.
    public let family: String
    public let weight: FontWeight
    public let style: FontStyle
    /// The PostScript name the request was made from, where it was made from one.
    public let postScriptName: String?

    public init(family: String, weight: FontWeight = .regular, style: FontStyle = .upright) {
        self.family = family
        self.weight = weight
        self.style = style
        self.postScriptName = nil
    }

    /// Reads a PostScript font name: `Times-Roman`, `Times-BoldItalic`, `Helvetica-Oblique`,
    /// `Courier-Bold`.  The part after the last hyphen gives the weight and style where it is
    /// one of the PostScript suffixes (`Roman`, `Regular`, `Bold`, `Italic`, `Oblique`, and
    /// their combinations); any other name is taken as a family whole.
    public init(postScriptName name: String) {
        self.postScriptName = name
        guard let hyphen = name.lastIndex(of: "-"), hyphen != name.startIndex,
              let (weight, style) = Self.suffix(name[name.index(after: hyphen)...]) else {
            (family, weight, style) = (name, .regular, .upright)
            return
        }
        family = String(name[..<hyphen])
        (self.weight, self.style) = (weight, style)
    }

    private static func suffix(_ suffix: Substring) -> (FontWeight, FontStyle)? {
        switch suffix.lowercased() {
        case "roman", "regular", "book", "normal":  return (.regular, .upright)
        case "bold":                                return (.bold, .upright)
        case "italic", "oblique":                   return (.regular, .italic)
        case "bolditalic", "boldoblique":           return (.bold, .italic)
        default:                                    return nil
        }
    }

    public var description: String {
        postScriptName ?? family + (weight == .bold ? " Bold" : "")
            + (style == .italic ? " Italic" : "")
    }

    /// The same request in another family, keeping its weight and style — how an alias is
    /// tried in place of the family asked for.
    func inFamily(_ family: String) -> FontRequest {
        FontRequest(family: family, weight: weight, style: style)
    }

    // MARK: - Aliases

    /// Families that stand in for the one asked for when it is not found, best first.
    ///
    /// The PostScript base 14 — Times, Helvetica, Courier — are the fonts §11.4.2 implies, and
    /// abcm2ps makes `serif` Times and `sans-serif` Helvetica.  Each is followed by the faces
    /// that ship in its place: the metric-compatible ones macOS and Windows carry, then the
    /// Liberation, Nimbus (URW base 35) and DejaVu families most Linux systems have.
    var aliases: [String] {
        switch Self.normalised(family) {
        case "times", "timesroman", "serif":
            return ["Times", "Times New Roman", "Liberation Serif", "Nimbus Roman",
                    "DejaVu Serif"]
        case "helvetica", "arial", "sansserif":
            return ["Helvetica", "Arial", "Liberation Sans", "Nimbus Sans", "DejaVu Sans"]
        case "courier", "couriernew", "monospace":
            return ["Courier", "Courier New", "Liberation Mono", "Nimbus Mono PS",
                    "DejaVu Sans Mono"]
        default:
            return []
        }
    }

    /// Every family some request falls back to, for listing what is installed.
    static let standInFamilies: [String] = ["Times", "Helvetica", "Courier"].flatMap {
        FontRequest(family: $0).aliases
    }

    /// A family name with case, spaces and hyphens taken out, so that "Times New Roman",
    /// "TimesNewRoman" and "times-new-roman" compare equal.
    static func normalised(_ family: String) -> String {
        String(family.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
