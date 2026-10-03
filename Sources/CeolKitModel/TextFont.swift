/// The kinds of text a font directive styles (ABC v2.2 §11.4.2; issue #186).
///
/// The raw value is the directive's name, without the `%%`.
public enum TextFontRole: String, CaseIterable, Sendable, Hashable, Codable {
    /// The first `T:` title.
    case title = "titlefont"
    /// Second and later `T:` titles.
    case subtitle = "subtitlefont"
    /// `C:` composers, with the `O:` origin appended.
    case composer = "composerfont"
    /// `P:` part labels.
    case parts = "partsfont"
    /// `Q:` tempo markings.
    case tempo = "tempofont"
    /// Chord symbols, and unprefixed quoted text printed on the chord line.
    case chordSymbol = "gchordfont"
    /// `"^…"`, `"_…"`, `"<…"`, `">…"` and `"@…"` annotations.
    case annotation = "annotationfont"
    /// Other printed information fields (`%%writefields`), such as `R:`.
    case info = "infofont"
    /// `%%text` and `%%begintext` blocks.
    case text = "textfont"
    /// `w:` lyrics aligned under the notes.
    case vocal = "vocalfont"
    /// `W:` words printed below the tune.
    case words = "wordsfont"
    /// The faces the in-string switches `$1` … `$4` select.
    case set1 = "setfont-1"
    case set2 = "setfont-2"
    case set3 = "setfont-3"
    case set4 = "setfont-4"
}

/// What a font directive sets: a face, a size, or both (ABC v2.2 §11.4.2).
///
/// `%%gchordfont Helvetica 12` sets both.  The size is optional, and abcm2ps's `*` in place
/// of the name keeps the face already in force — `%%vocalfont * 14` changes only the size —
/// so either half may be absent and leave that half as it was.
public struct FontSpec: Sendable, Hashable, Codable {
    /// The font's name as written: a PostScript name (`Times-Bold`), a family, or a generic
    /// family (`serif`, `sans-serif`, `monospace`).  `nil` keeps the face in force.
    public let name: String?
    /// The size in points.  `nil` keeps the size in force.
    public let size: Double?

    public init(name: String?, size: Double? = nil) {
        self.name = name
        self.size = size
    }

    /// `self` laid over `base`: each half this spec states replaces `base`'s, and each half
    /// it leaves out keeps `base`'s.
    public func overriding(_ base: FontSpec?) -> FontSpec {
        FontSpec(name: name ?? base?.name, size: size ?? base?.size)
    }
}
