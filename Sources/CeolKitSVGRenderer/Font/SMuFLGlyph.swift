/// Canonical SMuFL glyph names to their Unicode Private Use Area codepoints.
///
/// Names and codepoints are verified against **SMuFL 1.4** (March 2021, the current
/// revision) by `SMuFLGlyphConformanceTests`, which checks every case here against the
/// specification's published `glyphnames.json`.
///
/// This covers what the renderer actually draws, not the whole 2,940-glyph specification;
/// it grows as the renderer learns new notation. Cases may therefore be added freely, but
/// a case must never be removed or renamed without checking `glyphnames.json` first — a
/// wrong PUA codepoint does not fail, it silently engraves some other piece of notation.
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

    // Octave clefs (§4.6 `clef=treble-8`, `clef=bass+8`, …).  SMuFL draws the numeral as
    // part of the glyph, so the octave form is a substitution for the plain one and needs
    // no separate placement.  `cClef15ma`/`cClef15mb` and `fClef8vb`'s 15th are omitted
    // where Bravura has no glyph for them; see `octaveClef(_:shift:)` in `SVGEmitter`.
    case gClef8va
    case gClef8vb
    case gClef15ma
    case gClef15mb
    case fClef8va
    case fClef8vb
    case fClef15ma
    case fClef15mb
    case cClef8vb

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

    // Tuplets
    case tuplet0
    case tuplet1
    case tuplet2
    case tuplet3
    case tuplet4
    case tuplet5
    case tuplet6
    case tuplet7
    case tuplet8
    case tuplet9

    // Augmentation
    case augmentationDot

    // Repeat dots
    case repeatDot

    // Fermatas
    case fermataAbove
    case fermataBelow

    // Articulations (issue #264)
    case articAccentAbove
    case articAccentBelow
    case articStaccatoAbove
    case articStaccatoBelow
    case articTenutoAbove
    case articTenutoBelow
    case articStaccatissimoWedgeAbove
    case articStaccatissimoWedgeBelow
    case articMarcatoAbove
    case articMarcatoBelow

    // Bowing, technique and fingering (issue #264)
    case stringsUpBow
    case stringsDownBow
    /// The small circle §4.14 gives `!open!`: an open string or a harmonic.
    case stringsHarmonic
    case pluckedSnapPizzicatoAbove
    case pluckedSnapPizzicatoBelow
    case stringsThumbPosition
    case pluckedLeftHandPizzicato
    case fingering0
    case fingering1
    case fingering2
    case fingering3
    case fingering4
    case fingering5

    // Ornaments (issue #264)
    case ornamentTrill
    case ornamentTurn
    case ornamentTurnInverted
    case ornamentShortTrill
    case ornamentMordent
    /// One period of a trill's wavy line; repeated, the periods join into one line.
    case wiggleTrill
    /// One period of an arpeggio's wavy line, drawn along the baseline: turned to run up.
    case wiggleArpeggiatoUp

    // Staff brackets and braces
    case bracketTop
    case bracketBottom
    /// Stretchy: drawn at whatever height the staves it joins span, not at its natural one.
    case brace

    // Chord symbol accidentals: drawn on a text baseline, at text size (issue #184)
    case csymAccidentalFlat
    case csymAccidentalNatural
    case csymAccidentalSharp
    case csymAccidentalDoubleSharp
    case csymAccidentalDoubleFlat

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
        case .gClef8va:                    return 0xE053
        case .gClef8vb:                    return 0xE052
        case .gClef15ma:                   return 0xE054
        case .gClef15mb:                   return 0xE051
        case .fClef8va:                    return 0xE065
        case .fClef8vb:                    return 0xE064
        case .fClef15ma:                   return 0xE066
        case .fClef15mb:                   return 0xE063
        case .cClef8vb:                    return 0xE05D
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
        case .tuplet0:                     return 0xE880
        case .tuplet1:                     return 0xE881
        case .tuplet2:                     return 0xE882
        case .tuplet3:                     return 0xE883
        case .tuplet4:                     return 0xE884
        case .tuplet5:                     return 0xE885
        case .tuplet6:                     return 0xE886
        case .tuplet7:                     return 0xE887
        case .tuplet8:                     return 0xE888
        case .tuplet9:                     return 0xE889
        case .augmentationDot:             return 0xE1E7
        case .repeatDot:                   return 0xE044
        case .fermataAbove:                return 0xE4C0
        case .fermataBelow:                return 0xE4C1
        case .articAccentAbove:            return 0xE4A0
        case .articAccentBelow:            return 0xE4A1
        case .articStaccatoAbove:          return 0xE4A2
        case .articStaccatoBelow:          return 0xE4A3
        case .articTenutoAbove:            return 0xE4A4
        case .articTenutoBelow:            return 0xE4A5
        case .articStaccatissimoWedgeAbove: return 0xE4A8
        case .articStaccatissimoWedgeBelow: return 0xE4A9
        case .articMarcatoAbove:           return 0xE4AC
        case .articMarcatoBelow:           return 0xE4AD
        case .stringsDownBow:              return 0xE610
        case .stringsUpBow:                return 0xE612
        case .stringsHarmonic:             return 0xE614
        case .stringsThumbPosition:        return 0xE624
        case .pluckedSnapPizzicatoBelow:   return 0xE630
        case .pluckedSnapPizzicatoAbove:   return 0xE631
        case .pluckedLeftHandPizzicato:    return 0xE633
        case .fingering0:                  return 0xED10
        case .fingering1:                  return 0xED11
        case .fingering2:                  return 0xED12
        case .fingering3:                  return 0xED13
        case .fingering4:                  return 0xED14
        case .fingering5:                  return 0xED15
        case .ornamentTrill:               return 0xE566
        case .ornamentTurn:                return 0xE567
        case .ornamentTurnInverted:        return 0xE568
        case .ornamentShortTrill:          return 0xE56C
        case .ornamentMordent:             return 0xE56D
        case .wiggleTrill:                 return 0xEAA4
        case .wiggleArpeggiatoUp:          return 0xEAA9
        case .bracketTop:                  return 0xE003
        case .bracketBottom:               return 0xE004
        case .csymAccidentalFlat:          return 0xED60
        case .csymAccidentalNatural:       return 0xED61
        case .csymAccidentalSharp:         return 0xED62
        case .csymAccidentalDoubleSharp:   return 0xED63
        case .csymAccidentalDoubleFlat:    return 0xED64
        case .brace:                       return 0xE000
        }
    }
}
