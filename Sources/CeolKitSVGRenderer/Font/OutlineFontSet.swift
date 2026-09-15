import Foundation

/// The bundled faces, parsed for outline extraction and resolved the way the emitter asks
/// for them — by the `font-family` and `font-style` it would otherwise have written into a
/// `<text>` element.
///
/// Parsing is done once per process. Each face costs a few hundred kilobytes of tables and
/// a `cmap` dictionary, which is far cheaper than re-reading the OTF per page, and none of
/// it is mutable once built.
struct OutlineFontSet: Sendable {

    /// Identifies a face in the emitted document, so every glyph gets a stable `<defs>` id.
    enum FaceKey: String, Sendable, CaseIterable {
        case bravura
        case libertinusSerif
        case libertinusSerifItalic

        init(_ face: CeolKitFonts.Face) {
            switch face {
            case .bravura:                self = .bravura
            case .libertinusSerifRegular: self = .libertinusSerif
            case .libertinusSerifItalic:  self = .libertinusSerifItalic
            }
        }
    }

    private let fonts: [FaceKey: OpenTypeFont]

    /// The process-wide set, parsed on first use.
    ///
    /// `static let` gives thread-safe once-only initialisation without a lock. The failure
    /// is stored rather than thrown from the initialiser so that a broken resource reports
    /// the same error on every render instead of only the first.
    static func shared() throws -> OutlineFontSet {
        try cached.get()
    }

    private static let cached: Result<OutlineFontSet, OpenTypeError> = {
        var fonts: [FaceKey: OpenTypeFont] = [:]
        for face in CeolKitFonts.Face.allCases {
            switch parsed[face] ?? .failure(.faceUnavailable(face.rawValue)) {
            case .success(let font): fonts[FaceKey(face)] = font
            case .failure(let error): return .failure(error)
            }
        }
        return .success(OutlineFontSet(fonts: fonts))
    }()

    /// Each bundled face parsed on its own, so a caller asking for one face by name
    /// (``TextOutliner``) is not failed by a problem with another.
    private static let parsed: [CeolKitFonts.Face: Result<OpenTypeFont, OpenTypeError>] = {
        var parsed: [CeolKitFonts.Face: Result<OpenTypeFont, OpenTypeError>] = [:]
        for face in CeolKitFonts.Face.allCases {
            guard let data = try? CeolKitFonts.data(for: face) else {
                parsed[face] = .failure(.faceUnavailable(face.rawValue))
                continue
            }
            do {
                parsed[face] = .success(try OpenTypeFont.parse(data))
            } catch let error as OpenTypeError {
                parsed[face] = .failure(error)
            } catch {
                parsed[face] = .failure(.faceUnavailable(face.rawValue))
            }
        }
        return parsed
    }()

    /// One bundled face, parsed once per process.
    ///
    /// - Throws: ``CeolKitFontsError/resourceNotFound(_:)`` if the face is missing from the
    ///   bundle, or ``CeolKitFontsError/unreadable(_:)`` if it is present but cannot be
    ///   read or parsed.
    static func font(for face: CeolKitFonts.Face) throws -> OpenTypeFont {
        if case .success(let font) = parsed[face] { return font }
        _ = try CeolKitFonts.url(for: face)
        throw CeolKitFontsError.unreadable(face)
    }

    /// The face every run of ordinary text is set in — titles, footers, voice labels.
    ///
    /// `nil` where the bundled resource could not be read.  Layout asks for it to measure
    /// text it has to reserve space for, and has to keep working without it: a score that
    /// engraves with an estimated gutter is worth more than one that refuses to render.
    static func textFace() -> OpenTypeFont? {
        try? shared().resolve(family: CeolKitFonts.Face.libertinusSerifRegular.familyName,
                              italic: false)?.font
    }

    /// The face the emitter's `font-family` / `font-style` pair names, or `nil` for a
    /// family this renderer does not bundle.
    func resolve(family: String, italic: Bool) -> (key: FaceKey, font: OpenTypeFont)? {
        let key: FaceKey
        switch family {
        case CeolKitFonts.Face.bravura.familyName:
            key = .bravura
        case CeolKitFonts.Face.libertinusSerifRegular.familyName:
            key = italic ? .libertinusSerifItalic : .libertinusSerif
        default:
            return nil
        }
        guard let font = fonts[key] else { return nil }
        return (key, font)
    }
}
