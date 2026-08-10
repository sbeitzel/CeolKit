import Foundation

/// Errors raised while reading a bundled OpenType face.
///
/// Every case names something the parser can prove about the input rather than a generic
/// failure, because the only way these fire in practice is a bad resource swap — and then
/// the message is the whole diagnosis.
enum OpenTypeError: Error, Equatable {
    /// A read ran past the end of the data.
    case truncated(table: String, offset: Int)
    /// The file is not an sfnt, or is a collection rather than a single face.
    case notAnOpenTypeFont
    /// A table CeolKit requires is absent from the table directory.
    case missingTable(String)
    /// The face has no `cmap` subtable in a format the parser reads (4 or 12).
    case noUsableCharacterMap
    /// The `CFF ` table is structurally invalid.
    case malformedCFF(String)
    /// A Type 2 charstring used an operator the interpreter does not implement.
    case unsupportedCharstringOperator(String)
    /// A charstring nested subroutine calls deeper than the format permits.
    case charstringTooDeep
    /// The glyph index is outside the font's CharStrings INDEX.
    case glyphIndexOutOfRange(Int)
    /// A bundled face could not be read out of the module bundle at all.
    case faceUnavailable(String)
}

// MARK: - Byte access

/// Big-endian primitive reads over a font's bytes, bounds-checked.
///
/// Font files are attacker-adjacent input in the general case and simply untrusted here,
/// so every accessor is throwing rather than trapping: a malformed resource must surface
/// as a Swift error the renderer can report, never as a crash inside a server process.
struct FontBytes: Sendable {
    let bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var count: Int { bytes.count }

    func u8(_ offset: Int, _ table: String = "?") throws -> Int {
        guard offset >= 0, offset < bytes.count else {
            throw OpenTypeError.truncated(table: table, offset: offset)
        }
        return Int(bytes[offset])
    }

    func u16(_ offset: Int, _ table: String = "?") throws -> Int {
        guard offset >= 0, offset + 1 < bytes.count else {
            throw OpenTypeError.truncated(table: table, offset: offset)
        }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    func i16(_ offset: Int, _ table: String = "?") throws -> Int {
        Int(Int16(truncatingIfNeeded: try u16(offset, table)))
    }

    func u24(_ offset: Int, _ table: String = "?") throws -> Int {
        try u16(offset, table) << 8 | (try u8(offset + 2, table))
    }

    func u32(_ offset: Int, _ table: String = "?") throws -> Int {
        guard offset >= 0, offset + 3 < bytes.count else {
            throw OpenTypeError.truncated(table: table, offset: offset)
        }
        return Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
             | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
    }

    func tag(_ offset: Int) throws -> String {
        guard offset >= 0, offset + 3 < bytes.count else {
            throw OpenTypeError.truncated(table: "sfnt", offset: offset)
        }
        return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }
}

// MARK: - Font

/// A parsed OpenType/CFF face, sufficient to lay out and outline a run of text.
///
/// This exists because no SVG rasteriser outside a browser honours `@font-face`: every
/// one of them resolves `font-family` through a host font database that CeolKit cannot
/// populate portably. Reading the outlines here and emitting them as geometry moves the
/// rendering off the host's font environment and into the document, which is the only way
/// the same score rasterises identically on macOS and in a Linux container.
///
/// Scope is deliberately the minimum that serves that goal — `cmap`, `hmtx` and CFF
/// charstrings. There is no shaping, no kerning, no ligature substitution: the emitter
/// draws one glyph per Unicode scalar at its nominal advance, which is what the `<text>`
/// path it replaces effectively got from these faces anyway.
struct OpenTypeFont: Sendable {

    /// Design units per em, from `head`. Both bundled faces use 1000.
    let unitsPerEm: Double

    private let cmap: [UInt32: Int]
    private let advances: [Double]
    private let charstrings: Type2Interpreter

    var glyphCount: Int { charstrings.glyphCount }

    // MARK: Parsing

    static func parse(_ data: Data) throws -> OpenTypeFont {
        let bytes = FontBytes(data)
        let tables = try readTableDirectory(bytes)

        guard let head = tables["head"] else { throw OpenTypeError.missingTable("head") }
        let unitsPerEm = try bytes.u16(head + 18, "head")
        guard unitsPerEm > 0 else { throw OpenTypeError.malformedCFF("unitsPerEm is zero") }

        guard let maxp = tables["maxp"] else { throw OpenTypeError.missingTable("maxp") }
        let numGlyphs = try bytes.u16(maxp + 4, "maxp")

        guard let cmapOffset = tables["cmap"] else { throw OpenTypeError.missingTable("cmap") }
        let cmap = try readCharacterMap(bytes, at: cmapOffset, numGlyphs: numGlyphs)

        guard let hhea = tables["hhea"] else { throw OpenTypeError.missingTable("hhea") }
        guard let hmtx = tables["hmtx"] else { throw OpenTypeError.missingTable("hmtx") }
        let advances = try readAdvances(bytes, hhea: hhea, hmtx: hmtx, numGlyphs: numGlyphs)

        guard let cffOffset = tables["CFF "] else { throw OpenTypeError.missingTable("CFF ") }
        let cff = try CFFTable(bytes: bytes, offset: cffOffset)

        return OpenTypeFont(
            unitsPerEm: Double(unitsPerEm),
            cmap: cmap,
            advances: advances,
            charstrings: Type2Interpreter(cff: cff)
        )
    }

    private static func readTableDirectory(_ bytes: FontBytes) throws -> [String: Int] {
        let version = try bytes.u32(0, "sfnt")
        // 'OTTO' is a CFF-flavoured face; 0x00010000 and 'true' are glyf-flavoured. Only
        // CFF is read here, but the directory layout is shared, so accept both and let the
        // missing `CFF ` table be the error a TrueType face produces.
        let isCollection = (try? bytes.tag(0)) == "ttcf"
        guard !isCollection else { throw OpenTypeError.notAnOpenTypeFont }
        guard version == 0x4F54_544F || version == 0x0001_0000 || version == 0x7472_7565 else {
            throw OpenTypeError.notAnOpenTypeFont
        }
        let numTables = try bytes.u16(4, "sfnt")
        var tables: [String: Int] = [:]
        tables.reserveCapacity(numTables)
        for i in 0..<numTables {
            let record = 12 + 16 * i
            tables[try bytes.tag(record)] = try bytes.u32(record + 8, "sfnt")
        }
        return tables
    }

    /// Horizontal advances per glyph, in font units.
    ///
    /// `hmtx` stores full metrics only for the first `numberOfHMetrics` glyphs; every glyph
    /// beyond that repeats the last recorded advance. Both Libertinus faces rely on this
    /// (2589 metrics for 2640 glyphs), so the tail is not a theoretical case.
    private static func readAdvances(_ bytes: FontBytes, hhea: Int, hmtx: Int,
                                     numGlyphs: Int) throws -> [Double] {
        let numberOfHMetrics = max(1, try bytes.u16(hhea + 34, "hhea"))
        var advances: [Double] = []
        advances.reserveCapacity(numGlyphs)
        var last = 0.0
        for gid in 0..<numGlyphs {
            if gid < numberOfHMetrics {
                last = Double(try bytes.u16(hmtx + 4 * gid, "hmtx"))
            }
            advances.append(last)
        }
        return advances
    }

    // MARK: Character map

    private static func readCharacterMap(_ bytes: FontBytes, at cmap: Int,
                                         numGlyphs: Int) throws -> [UInt32: Int] {
        let numSubtables = try bytes.u16(cmap + 2, "cmap")
        // Preference order: full-repertoire Unicode first, then BMP, then the symbol
        // encoding. Bravura publishes its SMuFL codepoints under (3,1) and (3,10) alike,
        // so any of these resolves them; the order just avoids losing astral planes.
        let preference: [(Int, Int)] = [(3, 10), (0, 4), (0, 6), (3, 1), (0, 3), (0, 2), (0, 1), (0, 0)]
        var bestRank = preference.count
        var subtableOffset: Int?
        for i in 0..<numSubtables {
            let record = cmap + 4 + 8 * i
            let platform = try bytes.u16(record, "cmap")
            let encoding = try bytes.u16(record + 2, "cmap")
            guard let rank = preference.firstIndex(where: { $0 == (platform, encoding) }),
                  rank < bestRank else { continue }
            bestRank = rank
            subtableOffset = cmap + (try bytes.u32(record + 4, "cmap"))
        }
        guard let subtable = subtableOffset else { throw OpenTypeError.noUsableCharacterMap }

        switch try bytes.u16(subtable, "cmap") {
        case 4:  return try readCmapFormat4(bytes, at: subtable)
        case 12: return try readCmapFormat12(bytes, at: subtable, numGlyphs: numGlyphs)
        default: throw OpenTypeError.noUsableCharacterMap
        }
    }

    private static func readCmapFormat4(_ bytes: FontBytes, at base: Int) throws -> [UInt32: Int] {
        let segCount = try bytes.u16(base + 6, "cmap4") / 2
        let endCodes      = base + 14
        let startCodes    = endCodes + 2 * segCount + 2   // +2 skips reservedPad
        let idDeltas      = startCodes + 2 * segCount
        let idRangeOffsets = idDeltas + 2 * segCount

        var map: [UInt32: Int] = [:]
        for seg in 0..<segCount {
            let end   = try bytes.u16(endCodes + 2 * seg, "cmap4")
            let start = try bytes.u16(startCodes + 2 * seg, "cmap4")
            guard start <= end, end != 0xFFFF || start != 0xFFFF else { continue }
            let delta = try bytes.i16(idDeltas + 2 * seg, "cmap4")
            let rangeOffsetAddress = idRangeOffsets + 2 * seg
            let rangeOffset = try bytes.u16(rangeOffsetAddress, "cmap4")
            for code in start...end {
                let gid: Int
                if rangeOffset == 0 {
                    gid = (code + delta) & 0xFFFF
                } else {
                    let address = rangeOffsetAddress + rangeOffset + 2 * (code - start)
                    let raw = try bytes.u16(address, "cmap4")
                    gid = raw == 0 ? 0 : (raw + delta) & 0xFFFF
                }
                if gid != 0 { map[UInt32(code)] = gid }
            }
        }
        return map
    }

    private static func readCmapFormat12(_ bytes: FontBytes, at base: Int,
                                         numGlyphs: Int) throws -> [UInt32: Int] {
        let groupCount = try bytes.u32(base + 12, "cmap12")
        var map: [UInt32: Int] = [:]
        for group in 0..<groupCount {
            let record = base + 16 + 12 * group
            let start = try bytes.u32(record, "cmap12")
            let end   = try bytes.u32(record + 4, "cmap12")
            let startGlyph = try bytes.u32(record + 8, "cmap12")
            // A well-formed group cannot cover more codepoints than the font has glyphs;
            // rejecting the rest keeps a corrupt length field from materialising a
            // multi-million-entry dictionary.
            guard start <= end, end - start < numGlyphs else { continue }
            for code in start...end {
                let gid = startGlyph + (code - start)
                if gid != 0, gid < numGlyphs { map[UInt32(code)] = gid }
            }
        }
        return map
    }

    // MARK: Lookup

    /// The glyph index for `scalar`, or `nil` if the face does not encode it.
    func glyphID(for scalar: Unicode.Scalar) -> Int? {
        cmap[scalar.value]
    }

    /// The horizontal advance of `glyph` in font units, or `0` for an unknown index.
    func advance(forGlyph glyph: Int) -> Double {
        advances.indices.contains(glyph) ? advances[glyph] : 0
    }

    /// The outline of `glyph` in font units, y-up.
    func outline(forGlyph glyph: Int) throws -> GlyphPath {
        try charstrings.outline(forGlyph: glyph)
    }
}
