import Foundation

/// Faces a host app supplies for the renderer to draw text in (issue #190).
///
/// The host knows which fonts it ships and is licensed to use; this is how it hands them
/// over.  Give the library the bytes of each font file — OpenType/CFF or TrueType, a single
/// face or a collection (`.ttc`/`.otc`) — and set it on ``SVGRenderConfig/fontLibrary``.
/// Every face in it is then found by PostScript name or by family, weight and style before
/// any system font or bundled face is tried.
///
/// The faces are parsed once, here, so one library serves any number of renders; it is
/// immutable and safe to share across threads.  Registration is per configuration rather
/// than process-wide, so two renders with different libraries do not see each other's faces
/// and the same configuration always produces the same output.
///
/// ```swift
/// let library = try FontLibrary(fonts: [courierData, helveticaCollectionData])
/// var config = SVGRenderConfig()
/// config.fontLibrary = library
/// ```
public final class FontLibrary: Sendable {
    /// Every face the library holds, in the order the fonts were given and, within a
    /// collection, in face order.
    let faces: [OpenTypeFont]

    /// - Throws: ``FontLibraryError/unreadableFont(index:)`` for a font file — or any face
    ///   of a collection — that cannot be parsed, naming its position in `fonts`.
    public init(fonts: [Data]) throws {
        var faces: [OpenTypeFont] = []
        for (index, data) in fonts.enumerated() {
            do {
                let count = try OpenTypeFont.postScriptNames(in: data).count
                for face in 0..<count {
                    faces.append(try OpenTypeFont.parse(data, faceIndex: face))
                }
            } catch {
                throw FontLibraryError.unreadableFont(index: index)
            }
        }
        self.faces = faces
    }

    /// The PostScript names of the faces in the library, in order; a face that records
    /// none is left out.
    public var postScriptNames: [String] { faces.compactMap(\.postScriptName) }
}

public enum FontLibraryError: Error, Equatable, Sendable {
    /// The font at this position in the list given to ``FontLibrary/init(fonts:)`` is not
    /// one CeolKit can read: not OpenType or TrueType, or damaged.
    case unreadableFont(index: Int)
}
