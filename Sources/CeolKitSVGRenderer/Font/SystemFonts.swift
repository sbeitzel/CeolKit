import Foundation
#if canImport(CoreText)
import CoreText
#endif

/// The fonts installed on the machine, found through CoreText and read with CeolKit's own
/// parser (issue #190).
///
/// CoreText is asked only *where* a face is — the file and the face's PostScript name — and
/// the file is then read by ``OpenTypeFont`` like any other.  Every face, from whatever
/// source, is therefore outlined, measured and checked for embedding permission by the same
/// code, and a system face draws exactly as the same file registered by a host would.  A
/// face in a format the parser does not read is passed over.
///
/// Only Apple platforms have a lookup.  Elsewhere every query answers nothing, and a host
/// supplies its faces through ``FontLibrary`` instead; system lookup there would need
/// fontconfig, deferred until someone asks for it.
enum SystemFonts {

    /// Every installed face of `family`, in all its weights and styles.
    static func faces(family: String) -> [OpenTypeFont] {
        cached("family:" + FontRequest.normalised(family)) {
            #if canImport(CoreText)
            return locate([kCTFontFamilyNameAttribute: family],
                          mandatory: kCTFontFamilyNameAttribute)
            #else
            return []
            #endif
        }
    }

    /// The installed face whose PostScript name is `postScriptName`, if there is one.
    static func faces(postScriptName: String?) -> [OpenTypeFont] {
        guard let postScriptName else { return [] }
        return cached("name:" + postScriptName) {
            #if canImport(CoreText)
            return locate([kCTFontNameAttribute: postScriptName], mandatory: kCTFontNameAttribute)
                .filter { $0.postScriptName == postScriptName }
            #else
            return []
            #endif
        }
    }

    // MARK: - Cache

    // Process-wide: what is installed does not change during a render, and parsing a system
    // face is far dearer than looking it up.
    private nonisolated(unsafe) static var cache: [String: [OpenTypeFont]] = [:]
    private static let lock = NSLock()

    private static func cached(_ key: String, _ find: () -> [OpenTypeFont]) -> [OpenTypeFont] {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let found = find()
        lock.lock(); defer { lock.unlock() }
        cache[key] = found
        return found
    }

    // MARK: - CoreText

    #if canImport(CoreText)
    /// The faces CoreText matches to `attributes`, holding `mandatory` to an exact match —
    /// otherwise CoreText answers every query with *some* face, and a request for a family
    /// that is not installed would come back as Helvetica.
    private static func locate(_ attributes: [CFString: Any], mandatory: CFString) -> [OpenTypeFont] {
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let required: Set<String> = [mandatory as String]
        guard let matches = CTFontDescriptorCreateMatchingFontDescriptors(
                descriptor, required as CFSet) as? [CTFontDescriptor] else { return [] }
        var files: [URL: Data] = [:]
        return matches.compactMap { match in
            guard let url = CTFontDescriptorCopyAttribute(match, kCTFontURLAttribute) as? URL,
                  let name = CTFontDescriptorCopyAttribute(match, kCTFontNameAttribute) as? String
            else { return nil }
            guard let data = files[url] ?? (try? Data(contentsOf: url)) else { return nil }
            files[url] = data
            return try? OpenTypeFont.parse(data, postScriptName: name)
        }
    }
    #endif
}
