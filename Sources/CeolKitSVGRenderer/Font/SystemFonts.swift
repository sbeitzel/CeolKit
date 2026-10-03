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

    /// Every installed face in a format the parser reads, for listing (issue #191).
    ///
    /// Described by CoreText rather than parsed: reading every font file on a machine takes
    /// minutes, and a listing needs only names, weight, style, format and the licence's
    /// embedding bits — all of which CoreText has, the last two straight from the `OS/2`
    /// table the provider itself reads.  Remembered after the first call.
    static var listing: [FontFaceInfo] {
        listingLock.lock(); defer { listingLock.unlock() }
        if let listingCache { return listingCache }
        #if canImport(CoreText)
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection)
            as? [CTFontDescriptor] ?? []
        var faces = descriptors.compactMap(describe)
        // macOS leaves some faces out of the collection — Courier and Times among them —
        // that a lookup by name still finds, so the families a document is likeliest to
        // name are asked for by name as well.
        var seen = Set(faces.map(\.postScriptName))
        for family in FontRequest.standInFamilies {
            let match = CTFontDescriptorCreateWithAttributes(
                [kCTFontFamilyNameAttribute: family] as CFDictionary)
            let required: Set<String> = [kCTFontFamilyNameAttribute as String]
            for found in CTFontDescriptorCreateMatchingFontDescriptors(match, required as CFSet)
                    as? [CTFontDescriptor] ?? [] {
                guard let face = describe(found), seen.insert(face.postScriptName).inserted
                else { continue }
                faces.append(face)
            }
        }
        #else
        let faces: [FontFaceInfo] = []
        #endif
        listingCache = faces
        return faces
    }

    private nonisolated(unsafe) static var listingCache: [FontFaceInfo]?
    private static let listingLock = NSLock()

    #if canImport(CoreText)
    private static func describe(_ descriptor: CTFontDescriptor) -> FontFaceInfo? {
        guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
              let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
              let rawFormat = CTFontDescriptorCopyAttribute(descriptor, kCTFontFormatAttribute) as? UInt32
        else { return nil }
        let format: FontFaceInfo.Format
        switch CTFontFormat(rawValue: rawFormat) {
        case .openTypePostScript:        format = .cff
        case .openTypeTrueType, .trueType: format = .trueType
        default:                         return nil   // Type 1, bitmap: not read
        }
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        // OS/2: usWeightClass at 4, fsType at 8.  No table reads as regular and
        // unrestricted, as ``OpenTypeFont`` reads it.
        var weightClass = 400, fsType = 0
        if let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?,
           os2.count >= 10 {
            let bytes = [UInt8](os2.prefix(10))
            weightClass = Int(bytes[4]) << 8 | Int(bytes[5])
            fsType = Int(bytes[8]) << 8 | Int(bytes[9])
        } else if CTFontGetSymbolicTraits(font).contains(.traitBold) {
            weightClass = 700
        }
        return FontFaceInfo(
            postScriptName: name, family: family,
            weight: weightClass >= 600 ? .bold : .regular,
            style: CTFontGetSymbolicTraits(font).contains(.traitItalic) ? .italic : .upright,
            origin: .system, format: format,
            embeddable: EmbeddingPermissions(fsType: fsType).allowsOutlineEmbedding)
    }
    #endif

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
