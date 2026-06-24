/// SMuFL glyph names to Unicode PUA codepoints, covering the v0.1 glyph set.
public enum SMuFLGlyph: String, Sendable, CaseIterable {
    // Noteheads
    case noteheadBlack
    case noteheadHalf
    case noteheadWhole

    // Clefs
    case gClef
    case fClef
    case cClef
    case unpitchedPercussionClef1

    // Accidentals
    case accidentalSharp
    case accidentalFlat
    case accidentalNatural
    case accidentalDoubleSharp
    case accidentalDoubleFlat

    // Rests
    case restWhole
    case restHalf
    case restQuarter
    case rest8th
    case rest16th
    case rest32nd
    case rest64th

    // Flags
    case flag8thUp
    case flag8thDown
    case flag16thUp
    case flag16thDown
    case flag32ndUp
    case flag32ndDown

    // Time signatures
    case timeSig0
    case timeSig1
    case timeSig2
    case timeSig3
    case timeSig4
    case timeSig5
    case timeSig6
    case timeSig7
    case timeSig8
    case timeSig9
    case timeSigCommon
    case timeSigCutCommon

    // Augmentation
    case augmentationDot

    // Repeat dots
    case repeatDot

    // Fermatas
    case fermataAbove
    case fermataBelow

    public var unicodeScalar: Unicode.Scalar {
        // swiftlint:disable:next force_unwrapping — all values are valid PUA codepoints
        Unicode.Scalar(codepoint)!
    }

    public var character: Character { Character(unicodeScalar) }

    private var codepoint: UInt32 {
        switch self {
        case .noteheadBlack:               return 0xE0A4
        case .noteheadHalf:                return 0xE0A3
        case .noteheadWhole:               return 0xE0A2
        case .gClef:                       return 0xE050
        case .fClef:                       return 0xE062
        case .cClef:                       return 0xE05C
        case .unpitchedPercussionClef1:    return 0xE069
        case .accidentalSharp:             return 0xE262
        case .accidentalFlat:              return 0xE260
        case .accidentalNatural:           return 0xE261
        case .accidentalDoubleSharp:       return 0xE263
        case .accidentalDoubleFlat:        return 0xE264
        case .restWhole:                   return 0xE4E3
        case .restHalf:                    return 0xE4E4
        case .restQuarter:                 return 0xE4E5
        case .rest8th:                     return 0xE4E6
        case .rest16th:                    return 0xE4E7
        case .rest32nd:                    return 0xE4E8
        case .rest64th:                    return 0xE4E9
        case .flag8thUp:                   return 0xE240
        case .flag8thDown:                 return 0xE241
        case .flag16thUp:                  return 0xE242
        case .flag16thDown:                return 0xE243
        case .flag32ndUp:                  return 0xE244
        case .flag32ndDown:                return 0xE245
        case .timeSig0:                    return 0xE080
        case .timeSig1:                    return 0xE081
        case .timeSig2:                    return 0xE082
        case .timeSig3:                    return 0xE083
        case .timeSig4:                    return 0xE084
        case .timeSig5:                    return 0xE085
        case .timeSig6:                    return 0xE086
        case .timeSig7:                    return 0xE087
        case .timeSig8:                    return 0xE088
        case .timeSig9:                    return 0xE089
        case .timeSigCommon:               return 0xE08A
        case .timeSigCutCommon:            return 0xE08B
        case .augmentationDot:             return 0xE1E7
        case .repeatDot:                   return 0xE044
        case .fermataAbove:                return 0xE4C0
        case .fermataBelow:                return 0xE4C1
        }
    }
}
