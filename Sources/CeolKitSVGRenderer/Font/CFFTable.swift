/// The `CFF ` table: charstrings and the subroutine sets they call into.
///
/// Only what outline extraction needs is read. The charset, encoding, and String INDEX are
/// skipped — glyphs are reached through the face's `cmap`, never by PostScript name, so the
/// ~400 standard strings those tables index into would be dead weight.
struct CFFTable: Sendable {

    let bytes: FontBytes
    /// Byte ranges of each glyph's charstring, indexed by glyph ID.
    let charStrings: [Range<Int>]
    let globalSubrs: [Range<Int>]

    /// Local subroutines for a non-CID face; empty when the face is CID-keyed.
    private let singleLocalSubrs: [Range<Int>]
    /// Local subroutines per Font DICT, for CID-keyed faces.
    private let fdLocalSubrs: [[Range<Int>]]
    /// Font DICT index per glyph, for CID-keyed faces.
    private let fdSelect: [Int]

    var glyphCount: Int { charStrings.count }

    /// The local subroutine set a glyph's charstring may call.
    ///
    /// A CID-keyed face partitions its glyphs across Font DICTs, each with its own Private
    /// DICT and therefore its own subroutines, so this cannot be a single font-wide array.
    /// Neither bundled face is CID-keyed today, but a face that became one would otherwise
    /// produce silently mangled outlines rather than an error.
    func localSubrs(forGlyph glyph: Int) -> [Range<Int>] {
        guard !fdLocalSubrs.isEmpty else { return singleLocalSubrs }
        guard fdSelect.indices.contains(glyph) else { return [] }
        let fd = fdSelect[glyph]
        return fdLocalSubrs.indices.contains(fd) ? fdLocalSubrs[fd] : []
    }

    // MARK: - Parsing

    init(bytes: FontBytes, offset: Int) throws {
        self.bytes = bytes

        let headerSize = try bytes.u8(offset + 2, "CFF")
        // Name INDEX, then Top DICT INDEX, then String INDEX, then Global Subr INDEX —
        // each immediately after the last, so they can only be reached in sequence.
        let nameIndex   = try Self.readIndex(bytes, at: offset + headerSize)
        let topDictIndex = try Self.readIndex(bytes, at: nameIndex.end)
        let stringIndex = try Self.readIndex(bytes, at: topDictIndex.end)
        globalSubrs = try Self.readIndex(bytes, at: stringIndex.end).items

        guard let topDictRange = topDictIndex.items.first else {
            throw OpenTypeError.malformedCFF("Top DICT INDEX is empty")
        }
        let topDict = try Self.readDict(bytes, in: topDictRange)

        if let type = topDict[1200 + 6]?.first, type != 2 {
            throw OpenTypeError.malformedCFF("CharstringType \(Int(type)) is not supported")
        }

        guard let charStringsOffset = topDict[17]?.first.map({ offset + Int($0) }) else {
            throw OpenTypeError.malformedCFF("Top DICT has no CharStrings offset")
        }
        charStrings = try Self.readIndex(bytes, at: charStringsOffset).items

        if topDict[1200 + 30] != nil {
            // CID-keyed: subroutines live in the Private DICT of each Font DICT.
            singleLocalSubrs = []
            guard let fdArrayOffset = topDict[1200 + 36]?.first.map({ offset + Int($0) }),
                  let fdSelectOffset = topDict[1200 + 37]?.first.map({ offset + Int($0) }) else {
                throw OpenTypeError.malformedCFF("CID font is missing FDArray or FDSelect")
            }
            fdLocalSubrs = try Self.readIndex(bytes, at: fdArrayOffset).items.map { fontDictRange in
                let fontDict = try Self.readDict(bytes, in: fontDictRange)
                return try Self.readLocalSubrs(bytes, privateEntry: fontDict[18], cffOffset: offset)
            }
            fdSelect = try Self.readFDSelect(bytes, at: fdSelectOffset, glyphCount: charStrings.count)
        } else {
            singleLocalSubrs = try Self.readLocalSubrs(bytes, privateEntry: topDict[18], cffOffset: offset)
            fdLocalSubrs = []
            fdSelect = []
        }
    }

    /// The Subrs INDEX named by a `Private` DICT entry, whose operands are `[size, offset]`.
    ///
    /// The Subrs offset inside a Private DICT is relative to that DICT's own start, not to
    /// the table — the one place in CFF where an offset is not table-relative.
    private static func readLocalSubrs(_ bytes: FontBytes, privateEntry: [Double]?,
                                       cffOffset: Int) throws -> [Range<Int>] {
        guard let entry = privateEntry, entry.count >= 2 else { return [] }
        let privateOffset = cffOffset + Int(entry[1])
        let privateSize = Int(entry[0])
        guard privateSize >= 0, privateOffset >= 0,
              privateOffset + privateSize <= bytes.count else {
            throw OpenTypeError.malformedCFF("Private DICT lies outside the table")
        }
        let privateDict = try readDict(bytes, in: privateOffset..<(privateOffset + privateSize))
        guard let subrsOffset = privateDict[19]?.first else { return [] }
        return try readIndex(bytes, at: privateOffset + Int(subrsOffset)).items
    }

    private static func readFDSelect(_ bytes: FontBytes, at offset: Int,
                                     glyphCount: Int) throws -> [Int] {
        switch try bytes.u8(offset, "FDSelect") {
        case 0:
            return try (0..<glyphCount).map { try bytes.u8(offset + 1 + $0, "FDSelect") }
        case 3:
            let rangeCount = try bytes.u16(offset + 1, "FDSelect")
            var select = [Int](repeating: 0, count: glyphCount)
            let sentinel = try bytes.u16(offset + 3 + 3 * rangeCount, "FDSelect")
            for i in 0..<rangeCount {
                let record = offset + 3 + 3 * i
                let first = try bytes.u16(record, "FDSelect")
                let fd = try bytes.u8(record + 2, "FDSelect")
                let next = i + 1 < rangeCount
                    ? try bytes.u16(record + 3, "FDSelect")
                    : sentinel
                for glyph in first..<min(next, glyphCount) where glyph >= 0 {
                    select[glyph] = fd
                }
            }
            return select
        default:
            throw OpenTypeError.malformedCFF("unsupported FDSelect format")
        }
    }

    // MARK: INDEX

    /// A CFF INDEX: a count, an offset array, then the concatenated items.
    ///
    /// Offsets are one-based and measured from the byte *before* the data, which is why
    /// `dataBase` subtracts one rather than pointing at the first item.
    static func readIndex(_ bytes: FontBytes, at offset: Int) throws -> (items: [Range<Int>], end: Int) {
        let count = try bytes.u16(offset, "CFF INDEX")
        guard count > 0 else { return ([], offset + 2) }

        let offSize = try bytes.u8(offset + 2, "CFF INDEX")
        guard (1...4).contains(offSize) else {
            throw OpenTypeError.malformedCFF("INDEX offSize \(offSize) out of range")
        }
        let offsetArray = offset + 3
        let dataBase = offsetArray + (count + 1) * offSize - 1

        func itemOffset(_ i: Int) throws -> Int {
            let at = offsetArray + i * offSize
            switch offSize {
            case 1:  return try bytes.u8(at, "CFF INDEX")
            case 2:  return try bytes.u16(at, "CFF INDEX")
            case 3:  return try bytes.u24(at, "CFF INDEX")
            default: return try bytes.u32(at, "CFF INDEX")
            }
        }

        var items: [Range<Int>] = []
        items.reserveCapacity(count)
        var previous = try itemOffset(0)
        for i in 1...count {
            let next = try itemOffset(i)
            guard next >= previous, dataBase + next <= bytes.count else {
                throw OpenTypeError.malformedCFF("INDEX item \(i - 1) lies outside the table")
            }
            items.append((dataBase + previous)..<(dataBase + next))
            previous = next
        }
        return (items, dataBase + previous)
    }

    // MARK: DICT

    /// A CFF DICT as operator-to-operand-list. Two-byte (escaped) operators are keyed as
    /// `1200 + op`, keeping the whole thing in one flat dictionary.
    static func readDict(_ bytes: FontBytes, in range: Range<Int>) throws -> [Int: [Double]] {
        var dict: [Int: [Double]] = [:]
        var operands: [Double] = []
        var i = range.lowerBound
        while i < range.upperBound {
            let b0 = try bytes.u8(i, "CFF DICT")
            switch b0 {
            case 12:
                dict[1200 + (try bytes.u8(i + 1, "CFF DICT"))] = operands
                operands = []
                i += 2
            case 0...21:
                dict[b0] = operands
                operands = []
                i += 1
            case 28:
                operands.append(Double(try bytes.i16(i + 1, "CFF DICT")))
                i += 3
            case 29:
                operands.append(Double(Int32(truncatingIfNeeded: try bytes.u32(i + 1, "CFF DICT"))))
                i += 5
            case 30:
                let (value, length) = try readRealNumber(bytes, at: i + 1)
                operands.append(value)
                i += 1 + length
            case 32...246:
                operands.append(Double(b0 - 139))
                i += 1
            case 247...250:
                operands.append(Double((b0 - 247) * 256 + (try bytes.u8(i + 1, "CFF DICT")) + 108))
                i += 2
            case 251...254:
                operands.append(Double(-(b0 - 251) * 256 - (try bytes.u8(i + 1, "CFF DICT")) - 108))
                i += 2
            default:
                throw OpenTypeError.malformedCFF("reserved DICT byte \(b0)")
            }
        }
        return dict
    }

    /// A nibble-encoded real operand, returning its value and how many bytes it occupied.
    private static func readRealNumber(_ bytes: FontBytes, at offset: Int) throws -> (Double, Int) {
        var text = ""
        var i = offset
        while true {
            let byte = try bytes.u8(i, "CFF DICT")
            i += 1
            for nibble in [byte >> 4, byte & 0x0F] {
                switch nibble {
                case 0...9: text += String(nibble)
                case 0xA:   text += "."
                case 0xB:   text += "E"
                case 0xC:   text += "E-"
                case 0xE:   text += "-"
                case 0xF:   return (Double(text) ?? 0, i - offset)
                default:    break  // 0xD is reserved
                }
            }
        }
    }
}
