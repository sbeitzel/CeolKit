#if !canImport(CoreText) && canImport(Glibc)
import Foundation
import Glibc

/// The installed fonts fontconfig knows about, reached with `dlopen` (issue #206).
///
/// Loaded at first use rather than linked, so building CeolKit on Linux needs no
/// fontconfig headers, and a host without the library still runs: every query then answers
/// nothing, which is how system lookup behaved on Linux before there was any.
///
/// Only `FcFontList` is used, never `FcFontMatch`.  A match always answers with *some*
/// face — the nearest fontconfig can find — and a request for a family that is not
/// installed must find nothing, so that the provider's own stand-ins and diagnostics apply.
/// It is the same trap CoreText's mandatory attributes avoid on Apple platforms.
enum Fontconfig {
    /// One face fontconfig lists: where it is, and what it is called.
    struct Face: Sendable {
        let file: String
        let index: Int
        let postScriptName: String?
        let family: String?
        /// `FC_FONTFORMAT`: "CFF", "TrueType", "Type 1", "PCF", …
        let format: String?

        /// Whether ``OpenTypeFont`` can read the face: an `.otf` or a `.ttf`/`.ttc`.
        var isReadable: Bool { format == "CFF" || format == "TrueType" }
    }

    /// Every face whose `property` is `value` — `("family", "Liberation Serif")`,
    /// `("postscriptname", "LiberationSerif-Bold")` — or every face there is, for `nil`.
    static func list(_ property: (String, String)? = nil) -> [Face] {
        guard let api = API.shared, let pattern = api.patternCreate() else { return [] }
        defer { api.patternDestroy(pattern) }
        if let (name, value) = property {
            _ = value.withCString { text in
                text.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count + 1) {
                    api.patternAddString(pattern, name, $0)
                }
            }
        }
        guard let objects = api.objectSetCreate() else { return [] }
        defer { api.objectSetDestroy(objects) }
        for object in ["file", "index", "postscriptname", "family", "fontformat"] {
            _ = api.objectSetAdd(objects, object)
        }
        guard let set = api.fontList(api.config, pattern, objects) else { return [] }
        defer { api.fontSetDestroy(set) }

        // FcFontSet { int nfont; int sfont; FcPattern **fonts; }
        let count = Int(set.load(as: Int32.self))
        let fontsOffset = MemoryLayout<Int32>.stride * 2
        guard count > 0,
              let fonts = set.load(fromByteOffset: fontsOffset,
                                   as: UnsafeMutablePointer<OpaquePointer?>?.self)
        else { return [] }

        return (0..<count).compactMap { i in
            guard let font = fonts[i], let file = api.string(font, "file") else { return nil }
            return Face(file: file, index: api.integer(font, "index") ?? 0,
                        postScriptName: api.string(font, "postscriptname"),
                        family: api.string(font, "family"),
                        format: api.string(font, "fontformat"))
        }
    }

    // MARK: - The library

    /// The handful of fontconfig entry points used, resolved once.
    private struct API: @unchecked Sendable {
        // `@unchecked Sendable`: function pointers and the process-lifetime configuration
        // fontconfig hands back; fontconfig's own calls are thread-safe from 2.10.

        typealias Pattern = OpaquePointer
        let patternCreate: @convention(c) () -> Pattern?
        let patternDestroy: @convention(c) (Pattern?) -> Void
        let patternAddString: @convention(c) (Pattern?, UnsafePointer<CChar>?,
                                              UnsafePointer<UInt8>?) -> Int32
        let patternGetString: @convention(c) (Pattern?, UnsafePointer<CChar>?, Int32,
                                              UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?) -> Int32
        let patternGetInteger: @convention(c) (Pattern?, UnsafePointer<CChar>?, Int32,
                                               UnsafeMutablePointer<Int32>?) -> Int32
        let objectSetCreate: @convention(c) () -> OpaquePointer?
        let objectSetAdd: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
        let objectSetDestroy: @convention(c) (OpaquePointer?) -> Void
        let fontList: @convention(c) (OpaquePointer?, Pattern?, OpaquePointer?) -> UnsafeMutableRawPointer?
        let fontSetDestroy: @convention(c) (UnsafeMutableRawPointer?) -> Void
        /// The configuration `FcInitLoadConfigAndFonts` built: the user's font directories,
        /// rejects and all.
        let config: OpaquePointer?

        /// `nil` where the library, or any entry point, is missing.
        static let shared: API? = {
            guard let handle = dlopen("libfontconfig.so.1", RTLD_NOW | RTLD_LOCAL) else { return nil }
            func symbol<T>(_ name: String, as type: T.Type) -> T? {
                dlsym(handle, name).map { unsafeBitCast($0, to: type) }
            }
            typealias InitFn = @convention(c) () -> OpaquePointer?
            guard let initialise = symbol("FcInitLoadConfigAndFonts", as: InitFn.self),
                  let patternCreate = symbol("FcPatternCreate", as: (@convention(c) () -> Pattern?).self),
                  let patternDestroy = symbol("FcPatternDestroy", as: (@convention(c) (Pattern?) -> Void).self),
                  let patternAddString = symbol("FcPatternAddString", as: (@convention(c) (Pattern?, UnsafePointer<CChar>?, UnsafePointer<UInt8>?) -> Int32).self),
                  let patternGetString = symbol("FcPatternGetString", as: (@convention(c) (Pattern?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?) -> Int32).self),
                  let patternGetInteger = symbol("FcPatternGetInteger", as: (@convention(c) (Pattern?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<Int32>?) -> Int32).self),
                  let objectSetCreate = symbol("FcObjectSetCreate", as: (@convention(c) () -> OpaquePointer?).self),
                  let objectSetAdd = symbol("FcObjectSetAdd", as: (@convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32).self),
                  let objectSetDestroy = symbol("FcObjectSetDestroy", as: (@convention(c) (OpaquePointer?) -> Void).self),
                  let fontList = symbol("FcFontList", as: (@convention(c) (OpaquePointer?, Pattern?, OpaquePointer?) -> UnsafeMutableRawPointer?).self),
                  let fontSetDestroy = symbol("FcFontSetDestroy", as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self),
                  let config = initialise()
            else { return nil }
            return API(patternCreate: patternCreate, patternDestroy: patternDestroy,
                       patternAddString: patternAddString, patternGetString: patternGetString,
                       patternGetInteger: patternGetInteger, objectSetCreate: objectSetCreate,
                       objectSetAdd: objectSetAdd, objectSetDestroy: objectSetDestroy,
                       fontList: fontList, fontSetDestroy: fontSetDestroy, config: config)
        }()

        /// `FcResultMatch`.
        private static let match: Int32 = 0

        func string(_ pattern: Pattern, _ object: String) -> String? {
            var value: UnsafeMutablePointer<UInt8>?
            guard patternGetString(pattern, object, 0, &value) == Self.match, let value
            else { return nil }
            return String(cString: value)
        }

        func integer(_ pattern: Pattern, _ object: String) -> Int? {
            var value: Int32 = 0
            guard patternGetInteger(pattern, object, 0, &value) == Self.match else { return nil }
            return Int(value)
        }
    }
}
#endif
