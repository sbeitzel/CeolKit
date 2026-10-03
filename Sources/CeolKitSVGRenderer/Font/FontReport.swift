import CeolKitModel
import Foundation

/// One face the renderer could draw text with (issue #191).
public struct FontFaceInfo: Sendable, Hashable, Codable {
    /// How a face's glyph outlines are stored.
    public enum Format: String, Sendable, Hashable, Codable {
        /// Compact Font Format outlines — an `.otf`.
        case cff
        /// TrueType `glyf` outlines — a `.ttf`, or a face of a `.ttc`.
        case trueType
    }

    public let postScriptName: String
    public let family: String
    public let weight: FontWeight
    public let style: FontStyle
    public let origin: FontOrigin
    public let format: Format
    /// Whether the face's licence (`OS/2.fsType`) lets its outlines be copied into a
    /// document.  Under ``TextRendering/outlines`` a face that does not is passed over.
    public let embeddable: Bool

    public init(postScriptName: String, family: String, weight: FontWeight, style: FontStyle,
                origin: FontOrigin, format: Format, embeddable: Bool) {
        self.postScriptName = postScriptName
        self.family = family
        self.weight = weight
        self.style = style
        self.origin = origin
        self.format = format
        self.embeddable = embeddable
    }

    init(_ font: OpenTypeFont, origin: FontOrigin, fallbackName: String) {
        self.init(postScriptName: font.postScriptName ?? fallbackName,
                  family: font.familyName ?? fallbackName,
                  weight: font.weightClass >= 600 ? .bold : .regular,
                  style: font.isItalic ? .italic : .upright,
                  origin: origin, format: font.isCFF ? .cff : .trueType,
                  embeddable: font.embedding.allowsOutlineEmbedding)
    }
}

extension CeolKitFonts {
    /// Every face a render under `config` could draw text with, in the order a request
    /// searches them: the host's ``SVGRenderConfig/fontLibrary``, then — only where
    /// ``SVGRenderConfig/systemFonts`` is on — the faces installed on the machine, then the
    /// faces CeolKit bundles (issue #191).
    ///
    /// With system lookup on this can list hundreds of faces; filter on ``FontFaceInfo/origin``
    /// for the part you want.
    public static func availableFaces(config: SVGRenderConfig = SVGRenderConfig()) -> [FontFaceInfo] {
        var faces: [FontFaceInfo] = []
        for font in config.fontLibrary?.faces ?? [] {
            faces.append(FontFaceInfo(font, origin: .registered, fallbackName: "?"))
        }
        if config.systemFonts {
            faces += SystemFonts.listing
                .sorted { ($0.family, $0.postScriptName) < ($1.family, $1.postScriptName) }
        }
        for face in Face.allCases {
            guard let font = try? OutlineFontSet.font(for: face) else { continue }
            faces.append(FontFaceInfo(font, origin: .bundled, fallbackName: face.rawValue))
        }
        return faces
    }
}

/// What one kind of text in a tune is set in, and what was asked for it (issue #191).
///
/// The answer to "which font did it really use?": ``resolution`` names the face drawn and
/// where it came from, and says (``FontResolution/isExact``) whether that is the face asked
/// for.
public struct TextFontReport: Sendable, Hashable {
    public let role: TextFontRole
    /// What the font directives in force, over the host's ``SVGRenderConfig/textFonts``,
    /// ask for; `nil` where nothing does and CeolKit's default stands.
    public let requested: FontSpec?
    /// Where the directive that named the face was written.  `nil` for a face only the
    /// host's configuration names, and for the default.
    public let source: SourceRange?
    /// The face the text is drawn in, and how it was chosen.
    public let resolution: FontResolution
    /// The size the text is set at, in points.  Text on the staff (chord symbols,
    /// annotations, lyrics) is scaled with the music; for ``TextFontRole/tempo`` this is
    /// the tempo in the title block, and a `Q:` in the music is scaled from it likewise.
    public let size: Double

    public init(role: TextFontRole, requested: FontSpec?, source: SourceRange?,
                resolution: FontResolution, size: Double) {
        self.role = role
        self.requested = requested
        self.source = source
        self.resolution = resolution
        self.size = size
    }

    /// One line describing the report: `titlefont Times-Bold 20 → LibertinusSerif-Bold 20
    /// (bundled, substituted)`.
    public var summary: String {
        var asked = ""
        if let requested {
            let parts = [requested.name, requested.size.map(Self.points)].compactMap { $0 }
            if !parts.isEmpty { asked = " " + parts.joined(separator: " ") }
        }
        var notes = [resolution.origin.rawValue]
        if requested == nil { notes.append("default") }
        else if !resolution.isExact { notes.append("substituted") }
        return "\(role.rawValue)\(asked) → \(resolution.postScriptName) \(Self.points(size))"
            + " (\(notes.joined(separator: ", ")))"
    }

    static func points(_ size: Double) -> String {
        size == size.rounded() ? String(Int(size)) : String(format: "%.2f", size)
    }
}

/// The fonts one tune's text is set in (issue #191).
public struct TuneFontReport: Sendable, Hashable {
    /// Index into `score.tunes`.
    public let tuneIndex: Int
    /// One entry per kind of text the renderer draws, in ``TextFontRole`` order.
    public let roles: [TextFontReport]

    public init(tuneIndex: Int, roles: [TextFontReport]) {
        self.tuneIndex = tuneIndex
        self.roles = roles
    }
}
