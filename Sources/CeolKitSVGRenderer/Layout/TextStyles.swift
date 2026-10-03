import CeolKitModel

/// A face found for a font directive, ready to measure and draw with (issue #186).
struct TextFace: Sendable {
    let key: OutlineFontSet.FaceKey
    let font: OpenTypeFont
    /// What a `<text>` element names in ``TextRendering/fontFace`` mode.
    let family: String
    let isItalic: Bool
    let isBold: Bool
    /// How the face was chosen, for reporting (issue #191).
    let resolution: FontResolution

    init(_ resolved: FontProvider.Resolved) {
        resolution = resolved.resolution
        key = resolved.key
        font = resolved.font
        family = resolved.resolution.family
        isItalic = resolved.resolution.style == .italic
        isBold = resolved.resolution.weight == .bold
    }

    /// Whether this is one of the faces CeolKit bundles, which `fontFace` mode embeds.
    var bundledFace: CeolKitFonts.Face? {
        CeolKitFonts.Face.allCases.first { OutlineFontSet.FaceKey($0) == key }
    }
}

/// How one kind of text is set: its size, and the face a font directive chose for it.
///
/// `face` is `nil` where no directive named a face — the text is then set in Libertinus
/// Serif, `italic` or not, by exactly the code that set it before font directives existed,
/// so a document that names no font is written as it always was.
struct TextStyle: Sendable {
    let face: TextFace?
    let size: Double
    /// Whether the default face is the italic one; read only where `face` is `nil`.
    let italic: Bool

    init(face: TextFace? = nil, size: Double, italic: Bool = false) {
        self.face = face
        self.size = size
        self.italic = italic
    }

    /// The face the text is set in: the directive's, or the Libertinus Serif face the
    /// default draws with, which is never a substitute for anything.
    var resolution: FontResolution {
        if let face { return face.resolution }
        let bundled: CeolKitFonts.Face = italic ? .libertinusSerifItalic : .libertinusSerifRegular
        return FontResolution(
            requested: FontRequest(family: bundled.familyName,
                                   style: italic ? .italic : .upright),
            postScriptName: bundled.rawValue, family: bundled.familyName, weight: .regular,
            style: italic ? .italic : .upright, origin: .bundled, refusedForEmbedding: [],
            searchedSystemFonts: false)
    }

    /// The face text in this style is measured with: the directive's, or Libertinus Serif.
    /// `nil` only where the bundled resource could not be read; callers estimate then.
    var measuringFont: OpenTypeFont? {
        face?.font ?? OutlineFontSet.textFace()
    }

    /// How wide `text` is drawn in this style.
    func width(of text: String) -> Double {
        LyricBand.width(of: text, font: measuringFont, fontSize: size)
    }

    /// The face's typographic ascender and descender at this size, the descender positive.
    var ascent: Double {
        size * (face.map { $0.font.ascender / $0.font.unitsPerEm }
                ?? LibertinusSerifMetrics.ascenderRatio)
    }
    var descent: Double {
        size * (face.map { -$0.font.descender / $0.font.unitsPerEm }
                ?? LibertinusSerifMetrics.descenderRatio)
    }
}

extension SVGBuilder {
    /// Draws `content` in `style`: through the face a directive chose, or as Libertinus Serif
    /// by family name, exactly as text without a style is drawn.
    mutating func text(_ content: String, x: Double, y: Double, style: TextStyle,
                       textAnchor: String = "start") {
        guard let face = style.face else {
            text(content, x: x, y: y, fontFamily: "Libertinus Serif", fontSize: style.size,
                 textAnchor: textAnchor, fontStyle: style.italic ? "italic" : nil)
            return
        }
        text(content, x: x, y: y, face: face, fontSize: style.size, textAnchor: textAnchor)
    }
}

/// The style of every kind of text one tune sets (issue #186).
///
/// Built from the font directives in force for the tune — the host's
/// ``SVGRenderConfig/textFonts`` first, then the file header's, then the tune's own (ABC v2.2
/// §4.23) — over CeolKit's defaults, which are abcm2ps's sizes (issue #203).
///
/// Every size, a directive's or a default, is in abcm2ps's units, in which a staff space is
/// ``nominalStaffSize``; it is drawn scaled with the staff, as abcm2ps scales every piece of
/// text with `%%scale` (issue #203).  Only the footer, which is not set here, stays absolute.
struct TextStyles: Sendable {
    var title: TextStyle
    var subtitle: TextStyle
    var composer: TextStyle
    var info: TextStyle
    /// The `Q:` tempo printed in the title block.
    var tempo: TextStyle
    var words: TextStyle
    var chordSymbol: TextStyle
    var annotation: TextStyle
    var vocal: TextStyle
    /// A `Q:` written in the music, printed above the staff where it falls.
    var tempoChange: TextStyle

    /// The staff space abcm2ps's font sizes are stated against: its staff is 24 units tall
    /// at `%%scale 1`.  A size of `n` is drawn at `n × staffSize / nominalStaffSize`.
    static let nominalStaffSize = 6.0

    /// abcm2ps's default size for each role it has a font for (`xxxfont.html`), in its units.
    static func defaultSize(_ role: TextFontRole) -> Double {
        switch role {
        case .title:       return 20
        case .subtitle:    return 16
        case .composer:    return 14
        case .parts:       return 15
        case .tempo:       return 15
        case .chordSymbol: return 12
        case .annotation:  return 12
        case .info:        return 14
        case .text:        return 16
        case .vocal:       return 13
        case .words:       return 16
        case .set1, .set2, .set3, .set4: return 12
        }
    }

    /// CeolKit's defaults for a tune whose (scaled) staff size is `staffSize`: abcm2ps's sizes,
    /// scaled with the staff, in Libertinus Serif.
    static func standard(staffSize: Double) -> TextStyles {
        let k = staffSize / nominalStaffSize
        func size(_ role: TextFontRole) -> Double { defaultSize(role) * k }
        return TextStyles(
            title: TextStyle(size: size(.title)),
            subtitle: TextStyle(size: size(.subtitle), italic: true),
            composer: TextStyle(size: size(.composer), italic: true),
            info: TextStyle(size: size(.info), italic: true),
            tempo: TextStyle(size: size(.tempo)),
            words: TextStyle(size: size(.words)),
            chordSymbol: TextStyle(size: size(.chordSymbol)),
            annotation: TextStyle(size: size(.annotation)),
            vocal: TextStyle(size: size(.vocal)),
            tempoChange: TextStyle(size: size(.tempo)))
    }

    /// One role's font, as a directive resolved it, for reporting.
    struct Resolution: Sendable {
        let role: TextFontRole
        let resolution: FontResolution
        let source: SourceRange?
    }

    /// The styles `specs` ask for over the defaults, with every face they name resolved
    /// through `provider`.
    ///
    /// - Parameters:
    ///   - staffSize: the tune's staff size, already scaled.  A directive's size is in
    ///     abcm2ps's units and is scaled with the staff, like the defaults.
    static func resolve(_ specs: [TextFontRole: FontSpec], sources: [TextFontRole: SourceRange],
                        provider: FontProvider?, staffSize: Double)
        -> (styles: TextStyles, resolutions: [Resolution]) {
        var styles = standard(staffSize: staffSize)
        var resolutions: [Resolution] = []
        let k = staffSize / nominalStaffSize

        func style(_ role: TextFontRole, _ base: TextStyle) -> TextStyle {
            guard let spec = specs[role] else { return base }
            let size = spec.size.map { $0 * k } ?? base.size
            guard let name = spec.name, let provider else {
                return TextStyle(face: base.face, size: size, italic: base.italic)
            }
            let resolved = provider.resolve(FontRequest(postScriptName: name))
            resolutions.append(Resolution(role: role, resolution: resolved.resolution,
                                          source: sources[role]))
            return TextStyle(face: TextFace(resolved), size: size)
        }

        styles.title = style(.title, styles.title)
        styles.subtitle = style(.subtitle, styles.subtitle)
        styles.composer = style(.composer, styles.composer)
        styles.info = style(.info, styles.info)
        styles.tempo = style(.tempo, styles.tempo)
        styles.words = style(.words, styles.words)
        styles.chordSymbol = style(.chordSymbol, styles.chordSymbol)
        styles.annotation = style(.annotation, styles.annotation)
        styles.vocal = style(.vocal, styles.vocal)
        styles.tempoChange = style(.tempo, styles.tempoChange)
        return (styles, resolutions)
    }

    /// The style text of `role` is set in, for a role this renderer draws; the `Q:` in the
    /// title block stands for `.tempo`.
    func style(for role: TextFontRole) -> TextStyle? {
        switch role {
        case .title:       return title
        case .subtitle:    return subtitle
        case .composer:    return composer
        case .info:        return info
        case .tempo:       return tempo
        case .words:       return words
        case .chordSymbol: return chordSymbol
        case .annotation:  return annotation
        case .vocal:       return vocal
        case .parts, .text, .set1, .set2, .set3, .set4: return nil
        }
    }

    /// What each kind of text drawn is set in, and what was asked for it (issue #191).
    func report(specs: [TextFontRole: FontSpec],
                sources: [TextFontRole: SourceRange]) -> [TextFontReport] {
        TextFontRole.allCases.compactMap { role in
            guard let style = style(for: role) else { return nil }
            return TextFontReport(role: role, requested: specs[role], source: sources[role],
                                  resolution: style.resolution, size: style.size)
        }
    }

    /// Every bundled face the styles draw with, for `fontFace` mode to embed.
    var bundledFaces: Set<CeolKitFonts.Face> {
        Set([title, subtitle, composer, info, tempo, words, chordSymbol, annotation, vocal,
             tempoChange].compactMap { $0.face?.bundledFace })
    }
}
