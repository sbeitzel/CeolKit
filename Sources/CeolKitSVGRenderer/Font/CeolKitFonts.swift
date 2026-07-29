import Foundation
#if canImport(CoreText)
import CoreText
#endif

/// Access to the fonts bundled with CeolKitSVGRenderer.
///
/// The emitted SVG embeds every face via `@font-face` data URIs, so browser-based
/// consumers need nothing from this type. Native rasterizers (e.g. SVGKit, which
/// resolves `font-family` through CoreText/NSFontManager) ignore `@font-face` and
/// can only match fonts already known to the process or to the system font
/// configuration. Such hosts must make the faces resolvable by family name before
/// rasterizing, or the score renders with staff lines and stems but no noteheads,
/// clefs, or rests.
///
/// On Apple platforms call ``register()`` once at startup. Elsewhere there is no
/// process font manager to register with; use ``install(into:)`` or ``data(for:)``
/// to hand the faces to whatever font system the rasterizer consults (fontconfig,
/// resvg's `fontdb`, FreeType, …).
public enum CeolKitFonts {

    /// A font face bundled with CeolKitSVGRenderer.
    ///
    /// The raw value is the resource's base name; ``familyName`` is what the
    /// emitted SVG matches on.
    public enum Face: String, CaseIterable, Sendable {
        /// SMuFL music font used for every notehead, clef, rest, accidental, and flag.
        case bravura                = "Bravura"
        /// Serif face used for titles, composer, and footer text.
        case libertinusSerifRegular = "LibertinusSerif-Regular"
        /// Italic serif face used for rhythm and other italicised header fields.
        case libertinusSerifItalic  = "LibertinusSerif-Italic"

        /// The family name a renderer matches on — the `font-family` value in the
        /// emitted SVG. Both Libertinus faces share one family, distinguished by style.
        public var familyName: String {
            self == .bravura ? "Bravura" : "Libertinus Serif"
        }

        /// Whether this face is the italic member of its family.
        public var isItalic: Bool { self == .libertinusSerifItalic }
    }

    /// The file URL of a bundled face inside the module bundle.
    ///
    /// - Throws: ``CeolKitFontsError/resourceNotFound(_:)`` if the resource is
    ///   missing from the bundle.
    public static func url(for face: Face) throws -> URL {
        guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: "otf") else {
            throw CeolKitFontsError.resourceNotFound(face)
        }
        return url
    }

    /// The raw OTF bytes of a bundled face, for hosts that install fonts
    /// programmatically rather than from a path.
    public static func data(for face: Face) throws -> Data {
        try Data(contentsOf: url(for: face))
    }

    /// The raw OTF bytes of a bundled face, base64-encoded for embedding in an
    /// SVG `@font-face` rule.
    public static func base64(for face: Face) throws -> String {
        try data(for: face).base64EncodedString()
    }

    /// Writes every bundled face into `directory` as `<name>.otf`, overwriting any
    /// existing file of the same name, and returns the written URLs in
    /// `Face.allCases` order.
    ///
    /// Intended for hosts whose font system takes paths rather than bytes — point
    /// fontconfig (or equivalent) at `directory` afterwards. Creates `directory`,
    /// including intermediates, if it does not already exist.
    @discardableResult
    public static func install(into directory: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return try Face.allCases.map { face in
            let destination = directory.appendingPathComponent("\(face.rawValue).otf")
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: url(for: face), to: destination)
            return destination
        }
    }

    /// Registers every bundled face with the current process's font manager, so
    /// "Bravura" and "Libertinus Serif" resolve by family name.
    ///
    /// Idempotent and thread-safe; calls after the first return the first call's
    /// result without repeating the work.
    ///
    /// - Returns: `true` if the faces were registered. `false` where no process
    ///   font manager exists (any platform without CoreText) or if registration
    ///   failed — use ``install(into:)`` or ``data(for:)`` on those platforms.
    @discardableResult
    public static func register() -> Bool {
        registration
    }

    private static let registration: Bool = {
        #if canImport(CoreText)
        guard let urls = try? Face.allCases.map({ try url(for: $0) }) else { return false }
        // CTFontManagerRegisterFontsForURL is the only non-deprecated CoreText entry
        // point that reports success synchronously; the CFArray variant returns Void
        // and delivers errors through a handler that may fire more than once.
        return urls.allSatisfy(registerSingle)
        #else
        return false
        #endif
    }()

    #if canImport(CoreText)
    private static func registerSingle(_ url: URL) -> Bool {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // A face the host already registered from the same file is not a failure.
        guard let cfError = error?.takeRetainedValue() else { return false }
        return CFErrorGetDomain(cfError) == kCTFontManagerErrorDomain
            && CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue
    }
    #endif
}

/// Errors thrown when a bundled font resource cannot be reached.
public enum CeolKitFontsError: Error, Equatable {
    /// The face's OTF is missing from the module bundle.
    case resourceNotFound(CeolKitFonts.Face)
}
