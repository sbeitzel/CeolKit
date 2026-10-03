import CeolKitModel
import Foundation

/// Where a resolved face came from.
public enum FontOrigin: String, Sendable, Hashable, Codable {
    /// A face the host supplied in its ``FontLibrary``.
    case registered
    /// A face installed on the machine, found because ``SVGRenderConfig/systemFonts`` is on.
    case system
    /// One of the faces CeolKit bundles: always present, and the last resort.
    case bundled
}

/// What a ``FontRequest`` was answered with, and why (issue #190).
///
/// A request is answered by the first source that has the face — the host's
/// ``FontLibrary``, then the system's fonts where they are enabled, then the bundle — trying
/// the family asked for before the families that stand in for it (``FontRequest`` lists
/// them for the PostScript base 14 and the generic families).  Where what was drawn is not
/// what was asked for, ``diagnostics(at:)`` says so.
public struct FontResolution: Sendable, Hashable {
    public let requested: FontRequest
    /// The face used: its PostScript name, family, weight and style.
    public let postScriptName: String
    public let family: String
    public let weight: FontWeight
    public let style: FontStyle
    public let origin: FontOrigin
    /// Faces that matched but were passed over because their licence forbids embedding
    /// (`OS/2.fsType`; see ``TextRendering/outlines``), by PostScript name.
    public let refusedForEmbedding: [String]

    /// Whether the face is the one asked for: the requested PostScript name, or the
    /// requested family in the requested weight and style.
    public var isExact: Bool {
        if let name = requested.postScriptName,
           name.caseInsensitiveCompare(postScriptName) == .orderedSame { return true }
        return FontRequest.normalised(family) == FontRequest.normalised(requested.family)
            && weight == requested.weight && style == requested.style
    }

    /// What a document naming this font should be told, reported at `source`: nothing for
    /// an exact match; a substitution otherwise — a note where a standard family was
    /// answered by one that stands in for it, a warning where the family was not found at
    /// all — and a warning for each face refused for its licence.
    public func diagnostics(at source: SourceRange) -> [Diagnostic] {
        var out = refusedForEmbedding.map { name in
            Diagnostic(severity: .warning, code: .fontNotEmbeddable,
                       message: "\(name) may not be embedded in a document (its licence "
                           + "restricts embedding); using \(postScriptName)",
                       source: source)
        }
        guard !isExact else { return out }
        let standIn = requested.aliases.contains {
            FontRequest.normalised($0) == FontRequest.normalised(family)
        }
        out.append(Diagnostic(
            severity: standIn ? .info : .warning, code: .fontSubstituted,
            message: "\(requested) not found; using \(postScriptName)", source: source))
        return out
    }
}

/// Finds the face to draw a run of text in (issue #190).
///
/// Sits between the emitter and the faces: the host's ``FontLibrary``, the system's fonts
/// where ``SVGRenderConfig/systemFonts`` allows them, and the bundled faces, in that order.
/// Each request is resolved once per provider and remembered, so a render that sets a
/// thousand chord symbols in one face looks it up once.
///
/// The bundled families the emitter itself names — Bravura, Libertinus Serif — resolve
/// straight to the bundle, exactly as they did before there was anywhere else to look: a
/// document that names nothing else is written byte-for-byte as it was.
final class FontProvider: @unchecked Sendable {
    /// A face ready to draw: the key its glyphs are stored under, the face, and the account
    /// of how it was chosen.
    struct Resolved: Sendable {
        let key: OutlineFontSet.FaceKey
        let font: OpenTypeFont
        let resolution: FontResolution
    }

    private let library: FontLibrary?
    private let systemFonts: Bool
    /// Whether faces are copied into the document as outlines, so that a face whose licence
    /// forbids embedding has to be passed over.
    private let outlinesEmbed: Bool
    private let bundled: OutlineFontSet

    // `@unchecked Sendable`: the cache is the only mutable state, and every access to it
    // holds `lock`.
    private let lock = NSLock()
    private var cache: [FontRequest: Resolved] = [:]

    init(library: FontLibrary?, systemFonts: Bool, outlinesEmbed: Bool) throws {
        self.library = library
        self.systemFonts = systemFonts
        self.outlinesEmbed = outlinesEmbed
        self.bundled = try OutlineFontSet.shared()
    }

    convenience init(config: SVGRenderConfig) throws {
        try self.init(library: config.fontLibrary, systemFonts: config.systemFonts,
                      outlinesEmbed: config.textRendering.emitsOutlines)
    }

    /// Every request answered so far, in no particular order.
    var resolutions: [FontResolution] {
        lock.lock(); defer { lock.unlock() }
        return cache.values.map(\.resolution)
    }

    /// The face the emitter's `font-family` / `font-style` pair names.  The bundled
    /// families go straight to the bundle; anything else is a ``FontRequest``.
    func resolve(family: String, italic: Bool) -> (key: OutlineFontSet.FaceKey, font: OpenTypeFont)? {
        if let face = bundled.resolve(family: family, italic: italic) { return face }
        let resolved = resolve(FontRequest(family: family, style: italic ? .italic : .upright))
        return (resolved.key, resolved.font)
    }

    func resolve(_ request: FontRequest) -> Resolved {
        lock.lock()
        if let hit = cache[request] { lock.unlock(); return hit }
        lock.unlock()

        let resolved = lookUp(request)
        lock.lock(); defer { lock.unlock() }
        cache[request] = resolved
        return resolved
    }

    // MARK: - Lookup

    private func lookUp(_ request: FontRequest) -> Resolved {
        var refused: [String] = []
        // The family asked for, then whatever stands in for it.
        var families = [request.family]
        for alias in request.aliases
        where !families.contains(where: { FontRequest.normalised($0) == FontRequest.normalised(alias) }) {
            families.append(alias)
        }

        for (index, family) in families.enumerated() {
            let wanted = index == 0 ? request : request.inFamily(family)
            let sources = candidateSources(for: wanted)
            // The exact face from any source beats a near miss from the first.
            for exact in [true, false] {
                for (origin, faces) in sources {
                    guard let face = best(in: faces, for: wanted, exact: exact,
                                          refused: &refused) else { continue }
                    return resolved(face, origin: origin, request: request, refused: refused)
                }
            }
        }
        return bundledFallback(request, refused: refused)
    }

    private func candidateSources(for request: FontRequest) -> [(FontOrigin, [OpenTypeFont])] {
        var sources: [(FontOrigin, [OpenTypeFont])] = []
        if let library { sources.append((.registered, library.faces)) }
        if systemFonts {
            let system = SystemFonts.faces(postScriptName: request.postScriptName)
                + SystemFonts.faces(family: request.family)
            if !system.isEmpty { sources.append((.system, system)) }
        }
        return sources
    }

    /// The face of `faces` that answers `request` best: its PostScript name, or its family
    /// in the nearest weight and style.  With `exact`, only a face matching the PostScript
    /// name, or the family, weight and style all three, will do.
    private func best(in faces: [OpenTypeFont], for request: FontRequest, exact: Bool,
                      refused: inout [String]) -> OpenTypeFont? {
        let wantedFamily = FontRequest.normalised(request.family)
        var candidates: [(face: OpenTypeFont, score: Int)] = []
        for face in faces {
            let name = face.postScriptName ?? ""
            let byName = request.postScriptName
                .map { name.caseInsensitiveCompare($0) == .orderedSame } ?? false
            let byFamily = face.familyName.map { FontRequest.normalised($0) == wantedFamily } ?? false
            guard byName || byFamily else { continue }
            let weightMatches = (face.weightClass >= 600) == (request.weight == .bold)
            let styleMatches = face.isItalic == (request.style == .italic)
            let score = byName ? 4 : (styleMatches ? 2 : 0) + (weightMatches ? 1 : 0)
            guard !exact || score >= 3 else { continue }
            if outlinesEmbed && !face.embedding.allowsOutlineEmbedding {
                if !refused.contains(name) { refused.append(name) }
                continue
            }
            candidates.append((face, score))
        }
        return candidates.max { $0.score < $1.score }?.face
    }

    private func resolved(_ face: OpenTypeFont, origin: FontOrigin, request: FontRequest,
                          refused: [String]) -> Resolved {
        let name = face.postScriptName ?? face.familyName ?? request.family
        return Resolved(
            key: OutlineFontSet.FaceKey(postScriptName: name),
            font: face,
            resolution: FontResolution(
                requested: request, postScriptName: name,
                family: face.familyName ?? request.family,
                weight: face.weightClass >= 600 ? .bold : .regular,
                style: face.isItalic ? .italic : .upright,
                origin: origin, refusedForEmbedding: refused))
    }

    /// The bundle's answer, which always exists: Bravura for Bravura, Libertinus Serif in
    /// the requested style for everything else.  The bundle has no bold.
    private func bundledFallback(_ request: FontRequest, refused: [String]) -> Resolved {
        let face: CeolKitFonts.Face =
            FontRequest.normalised(request.family) == "bravura" ? .bravura
            : request.style == .italic ? .libertinusSerifItalic : .libertinusSerifRegular
        let key = OutlineFontSet.FaceKey(face)
        // `shared()` succeeded in `init`, so every bundled face is there.
        let font = bundled.resolve(family: face.familyName, italic: face.isItalic)!.font
        return Resolved(
            key: key, font: font,
            resolution: FontResolution(
                requested: request, postScriptName: font.postScriptName ?? face.rawValue,
                family: face.familyName, weight: .regular,
                style: face.isItalic ? .italic : .upright,
                origin: .bundled, refusedForEmbedding: refused))
    }
}
