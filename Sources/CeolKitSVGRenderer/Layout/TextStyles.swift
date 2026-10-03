import CeolKitModel

/// A face found for a font directive, ready to measure and draw with (issue #186).
struct TextFace: Sendable {
    let key: OutlineFontSet.FaceKey
    let font: OpenTypeFont
    /// What a `<text>` element names in ``TextRendering/fontFace`` mode.
    let family: String
    let isItalic: Bool
    let isBold: Bool

    init(_ resolved: FontProvider.Resolved) {
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
/// §4.23) — over CeolKit's own defaults, which are the sizes and faces it has always used.
///
/// Text in the page's furniture (title, composer, info, the header tempo, words) is sized in
/// absolute points; text that belongs to the staff (chord symbols, annotations, lyrics, a
/// tempo change in the music) scales with `%%ceolkit:scale`, because the staff does.
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

    /// CeolKit's defaults for a tune whose (scaled) staff size is `staffSize`.
    static func standard(staffSize: Double) -> TextStyles {
        TextStyles(
            title: TextStyle(size: 18),
            subtitle: TextStyle(size: 12, italic: true),
            composer: TextStyle(size: 12, italic: true),
            info: TextStyle(size: 12, italic: true),
            tempo: TextStyle(size: 12),
            words: TextStyle(size: WordsBlock.fontSize),
            chordSymbol: TextStyle(size: AnnotationBand.fontSize(staffSize: staffSize)),
            annotation: TextStyle(size: AnnotationBand.fontSize(staffSize: staffSize)),
            vocal: TextStyle(size: LyricBand.fontSize(staffSize: staffSize)),
            tempoChange: TextStyle(size: staffSize * 1.5))
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
    ///   - staffSize: the tune's staff size, already scaled.
    ///   - scale: the tune's `%%ceolkit:scale`, which a directive's size for staff text is
    ///     multiplied by.
    static func resolve(_ specs: [TextFontRole: FontSpec], sources: [TextFontRole: SourceRange],
                        provider: FontProvider?, staffSize: Double, scale: Double)
        -> (styles: TextStyles, resolutions: [Resolution]) {
        var styles = standard(staffSize: staffSize)
        var resolutions: [Resolution] = []

        func style(_ role: TextFontRole, _ base: TextStyle, scales: Bool) -> TextStyle {
            guard let spec = specs[role] else { return base }
            let size = spec.size.map { scales ? $0 * scale : $0 } ?? base.size
            guard let name = spec.name, let provider else {
                return TextStyle(face: base.face, size: size, italic: base.italic)
            }
            let resolved = provider.resolve(FontRequest(postScriptName: name))
            resolutions.append(Resolution(role: role, resolution: resolved.resolution,
                                          source: sources[role]))
            return TextStyle(face: TextFace(resolved), size: size)
        }

        styles.title = style(.title, styles.title, scales: false)
        styles.subtitle = style(.subtitle, styles.subtitle, scales: false)
        styles.composer = style(.composer, styles.composer, scales: false)
        styles.info = style(.info, styles.info, scales: false)
        styles.tempo = style(.tempo, styles.tempo, scales: false)
        styles.words = style(.words, styles.words, scales: false)
        styles.chordSymbol = style(.chordSymbol, styles.chordSymbol, scales: true)
        styles.annotation = style(.annotation, styles.annotation, scales: true)
        styles.vocal = style(.vocal, styles.vocal, scales: true)
        styles.tempoChange = style(.tempo, styles.tempoChange, scales: true)
        return (styles, resolutions)
    }

    /// Every bundled face the styles draw with, for `fontFace` mode to embed.
    var bundledFaces: Set<CeolKitFonts.Face> {
        Set([title, subtitle, composer, info, tempo, words, chordSymbol, annotation, vocal,
             tempoChange].compactMap { $0.face?.bundledFace })
    }
}
