import Foundation

/// Errors raised while reading an OpenType face.
///
/// Every case names something the parser can prove about the input rather than a generic
/// failure, because the only way these fire in practice is a bad resource swap — and then
/// the message is the whole diagnosis.
enum OpenTypeError: Error, Equatable {
    /// A read ran past the end of the data.
    case truncated(table: String, offset: Int)
    /// The file is neither an sfnt nor a collection of them.
    case notAnOpenTypeFont
    /// A collection was asked for a face it does not have — by index, or by PostScript name.
    case faceNotFound(String)
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
    /// The glyph index is outside the font's CharStrings INDEX, or its `loca`.
    case glyphIndexOutOfRange(Int)
    /// A `glyf` glyph is structurally invalid.
    case malformedGlyph(String)
    /// Composite glyphs nest deeper than ``TrueTypeGlyphs/maxCompositeDepth`` — in practice,
    /// a composite that includes itself.
    case compositeTooDeep
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

/// A parsed OpenType face, sufficient to lay out and outline a run of text.
///
/// This exists because no SVG rasteriser outside a browser honours `@font-face`: every
/// one of them resolves `font-family` through a host font database that CeolKit cannot
/// populate portably. Reading the outlines here and emitting them as geometry moves the
/// rendering off the host's font environment and into the document, which is the only way
/// the same score rasterises identically on macOS and in a Linux container.
///
/// Scope is deliberately the minimum that serves that goal — `cmap`, `hmtx`, and outlines
/// from either CFF charstrings or TrueType `glyf` (issue #189), from a single face or one
/// face of a collection. There is no shaping, no kerning, no ligature substitution: the
/// emitter draws one glyph per Unicode scalar at its nominal advance, which is what the
/// `<text>` path it replaces effectively got from these faces anyway.  Variable fonts are
/// read at their default instance.
struct OpenTypeFont: Sendable {

    /// Design units per em, from `head`. Both bundled faces use 1000.
    let unitsPerEm: Double
    /// The face's typographic ascender in font units, positive above the baseline.
    let ascender: Double
    /// The face's typographic descender in font units, negative below the baseline.
    let descender: Double

    /// The face's PostScript name (`name` ID 6), where it records one.
    let postScriptName: String?
    /// What the face's licence lets a document do with it, from `OS/2.fsType`.
    let embedding: EmbeddingPermissions

    private let cmap: [UInt32: Int]
    private let advances: [Double]
    private let outlines: Outlines

    /// Where a face's glyph outlines come from.
    private enum Outlines: Sendable {
        case cff(Type2Interpreter)
        case trueType(TrueTypeGlyphs)
    }

    var glyphCount: Int {
        switch outlines {
        case .cff(let charstrings): return charstrings.glyphCount
        case .trueType(let glyphs): return glyphs.glyphCount
        }
    }

    // MARK: Parsing

    /// Parses one face: the file itself, or face `faceIndex` of a collection (`.ttc`/`.otc`).
    /// A plain font file has only face 0.
    static func parse(_ data: Data, faceIndex: Int = 0) throws -> OpenTypeFont {
        let bytes = FontBytes(data)
        let directories = try faceDirectories(bytes)
        guard directories.indices.contains(faceIndex) else {
            throw OpenTypeError.faceNotFound("#\(faceIndex)")
        }
        return try parse(bytes, directory: directories[faceIndex])
    }

    /// Parses the face of a font file or collection whose PostScript name is `postScriptName`
    /// — how a caller asking for `Helvetica-Bold` finds it in `Helvetica.ttc`.
    static func parse(_ data: Data, postScriptName: String) throws -> OpenTypeFont {
        let bytes = FontBytes(data)
        for directory in try faceDirectories(bytes) {
            let tables = try readTableDirectory(bytes, at: directory)
            if try readPostScriptName(bytes, tables: tables) == postScriptName {
                return try parse(bytes, directory: directory)
            }
        }
        throw OpenTypeError.faceNotFound(postScriptName)
    }

    /// The PostScript name of every face in a font file or collection, in face-index order;
    /// `nil` for a face that records none.
    static func postScriptNames(in data: Data) throws -> [String?] {
        let bytes = FontBytes(data)
        return try faceDirectories(bytes).map {
            try readPostScriptName(bytes, tables: try readTableDirectory(bytes, at: $0))
        }
    }

    private static func parse(_ bytes: FontBytes, directory: Int) throws -> OpenTypeFont {
        let tables = try readTableDirectory(bytes, at: directory)

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

        // OS/2 `sTypoAscender`/`sTypoDescender` are the values `LibertinusSerifMetrics`
        // records. `OS/2` is optional in a CFF face; `hhea` carries the same pair, and is
        // what a face without one is laid out with.
        let (ascender, descender): (Int, Int)
        if let os2 = tables["OS/2"] {
            ascender = try bytes.i16(os2 + 68, "OS/2")
            descender = try bytes.i16(os2 + 70, "OS/2")
        } else {
            ascender = try bytes.i16(hhea + 4, "hhea")
            descender = try bytes.i16(hhea + 6, "hhea")
        }

        let outlines: Outlines
        if let cffOffset = tables["CFF "] {
            outlines = .cff(Type2Interpreter(cff: try CFFTable(bytes: bytes, offset: cffOffset)))
        } else if let glyf = tables["glyf"] {
            guard let loca = tables["loca"] else { throw OpenTypeError.missingTable("loca") }
            outlines = .trueType(try TrueTypeGlyphs(
                bytes: bytes, glyf: glyf, loca: loca, numGlyphs: numGlyphs,
                longOffsets: try bytes.i16(head + 50, "head") == 1))
        } else {
            throw OpenTypeError.missingTable("CFF ")
        }

        return OpenTypeFont(
            unitsPerEm: Double(unitsPerEm),
            ascender: Double(ascender),
            descender: Double(descender),
            postScriptName: try readPostScriptName(bytes, tables: tables),
            embedding: EmbeddingPermissions(
                fsType: try tables["OS/2"].map { try bytes.u16($0 + 8, "OS/2") } ?? 0),
            cmap: cmap,
            advances: advances,
            outlines: outlines
        )
    }

    /// Where each face's table directory starts: the start of the file for a single face,
    /// or each offset a collection's `ttcf` header lists.
    private static func faceDirectories(_ bytes: FontBytes) throws -> [Int] {
        guard (try? bytes.tag(0)) == "ttcf" else { return [0] }
        let count = try bytes.u32(8, "ttcf")
        // Each offset is four bytes of header; a count the file cannot hold is corrupt.
        guard count > 0, 12 + 4 * count <= bytes.count else {
            throw OpenTypeError.truncated(table: "ttcf", offset: 8)
        }
        return try (0..<count).map { try bytes.u32(12 + 4 * $0, "ttcf") }
    }

    private static func readTableDirectory(_ bytes: FontBytes, at base: Int) throws -> [String: Int] {
        let version = try bytes.u32(base, "sfnt")
        // 'OTTO' is a CFF-flavoured face; 0x00010000 and 'true' are glyf-flavoured.
        guard version == 0x4F54_544F || version == 0x0001_0000 || version == 0x7472_7565 else {
            throw OpenTypeError.notAnOpenTypeFont
        }
        let numTables = try bytes.u16(base + 4, "sfnt")
        var tables: [String: Int] = [:]
        tables.reserveCapacity(numTables)
        for i in 0..<numTables {
            // Table offsets are from the start of the file, in a collection as in a face.
            let record = base + 12 + 16 * i
            tables[try bytes.tag(record)] = try bytes.u32(record + 8, "sfnt")
        }
        return tables
    }

    // MARK: Names

    /// `name` ID 6, the PostScript name: Unicode (platform 0) or Windows (3) records in
    /// UTF-16BE, Macintosh (1) in Roman, which for the ASCII a PostScript name is limited to
    /// is ASCII.  `nil` where the face has no `name` table or no such record.
    private static func readPostScriptName(_ bytes: FontBytes,
                                           tables: [String: Int]) throws -> String? {
        guard let name = tables["name"] else { return nil }
        let count = try bytes.u16(name + 2, "name")
        let storage = name + (try bytes.u16(name + 4, "name"))
        var fallback: String?
        for i in 0..<count {
            let record = name + 6 + 12 * i
            guard try bytes.u16(record + 6, "name") == 6 else { continue }
            let platform = try bytes.u16(record, "name")
            let length = try bytes.u16(record + 8, "name")
            let start = storage + (try bytes.u16(record + 10, "name"))
            guard start >= 0, start + length <= bytes.count else {
                throw OpenTypeError.truncated(table: "name", offset: start)
            }
            let raw = bytes.bytes[start..<(start + length)]
            switch platform {
            case 0, 3:
                let units = stride(from: raw.startIndex, to: raw.endIndex - 1, by: 2).map {
                    UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1])
                }
                return String(decoding: units, as: UTF16.self)
            case 1:
                fallback = fallback ?? String(decoding: raw, as: UTF8.self)
            default:
                continue
            }
        }
        return fallback
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
        switch outlines {
        case .cff(let charstrings): return try charstrings.outline(forGlyph: glyph)
        case .trueType(let glyphs): return try glyphs.outline(forGlyph: glyph)
        }
    }

    /// How wide `text` is drawn at `fontSize`, in points.
    ///
    /// Summed nominal advances of the ``OutlineRun`` that ``SVGBuilder`` and
    /// ``TextOutliner`` both draw `text` as — so a caller reserving space from this measure
    /// and the emitter drawing into it cannot disagree.
    func width(of text: String, fontSize: Double) -> Double {
        OutlineRun(text, font: self).advanceUnits * fontSize / unitsPerEm
    }
}

// MARK: - Embedding

/// What a face's licence lets a document do with it, read from `OS/2.fsType` (issue #189).
///
/// Drawing a run of text as glyph outlines copies those outlines into the document, which
/// is embedding in the licence's sense.  A caller choosing faces to outline asks
/// ``allowsOutlineEmbedding`` and falls back to another face where it is `false` (#190).
struct EmbeddingPermissions: Sendable, Equatable {
    /// The raw `OS/2.fsType` field; `0` where the face has no `OS/2` table.
    let fsType: Int

    /// Bits 0–3 say how the face may be embedded.  Only one should be set; where several
    /// are, the least restrictive applies (OpenType `OS/2` specification).
    private var usage: Int { fsType & 0x000F }

    /// Restricted License embedding: the face may not be embedded at all.
    var isRestricted: Bool { usage & 0x0002 != 0 && usage & 0x000C == 0 }
    /// Bit 8: the face must be embedded whole, never a subset of its glyphs.
    var forbidsSubsetting: Bool { fsType & 0x0100 != 0 }
    /// Bit 9: only bitmaps may be embedded, never outlines.
    var bitmapOnly: Bool { fsType & 0x0200 != 0 }

    /// Whether outlines of the glyphs a document uses may be copied into it.  An outline
    /// document embeds exactly the glyphs it draws — a subset — so a face that forbids
    /// subsetting is refused along with restricted and bitmap-only ones.
    var allowsOutlineEmbedding: Bool { !isRestricted && !bitmapOnly && !forbidsSubsetting }
}

// MARK: - Run layout

/// A run of text laid out the one way this module lays text out: one glyph per Unicode
/// scalar at its nominal advance.
///
/// There is no shaping, kerning, or ligature substitution. That is not a shortcut taken
/// against the `<text>` path outlines replace — a rasteriser handed the same string and
/// these faces applies no `GPOS`/`GSUB` either unless it runs a full shaper, so nominal
/// advances are what the font-face route was already producing.
///
/// The emitter, ``OpenTypeFont/width(of:fontSize:)`` and the public ``TextOutliner`` all go
/// through this, which is what keeps a run measured one way from being drawn another.
struct OutlineRun: Sendable {
    let font: OpenTypeFont
    /// Glyph indices in drawing order. An unencoded scalar falls back to glyph 0, whose
    /// `.notdef` box is what a rasteriser would have drawn: a visible gap beats a run that
    /// silently shortens.
    let glyphs: [Int]

    init(_ text: String, font: OpenTypeFont) {
        self.font = font
        self.glyphs = text.unicodeScalars.map { font.glyphID(for: $0) ?? 0 }
    }

    /// The run's total advance, in font units.
    var advanceUnits: Double {
        glyphs.reduce(0) { $0 + font.advance(forGlyph: $1) }
    }

    /// Each glyph paired with the pen position it is drawn at, starting from `startX` and
    /// advancing by `scaleX` page units per font unit.
    func placements(startX: Double, scaleX: Double) -> [(glyph: Int, penX: Double)] {
        var penX = startX
        return glyphs.map { glyph in
            defer { penX += font.advance(forGlyph: glyph) * scaleX }
            return (glyph, penX)
        }
    }
}
