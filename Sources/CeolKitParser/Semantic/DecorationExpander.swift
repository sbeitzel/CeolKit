import CeolKitModel

/// Maps syntactic DecorationToken values to their canonical Decoration enum cases.
/// Short-form characters are expanded per ABC v2.2 §4.14.
func expandDecoration(
    _ token: DecorationToken,
    userSymbols: [Character: Decoration]
) -> Decoration {
    switch token {
    case .shortForm(let ch):
        return expandShort(ch, userSymbols: userSymbols)
    case .longForm(let text):
        return expandLong(text)
    }
}

private func expandShort(_ ch: Character, userSymbols: [Character: Decoration]) -> Decoration {
    switch ch {
    case ".": return .staccato
    case "~": return .roll
    case "H": return .fermata
    case "L": return .accent
    case "M": return .mordent
    case "O": return .coda
    case "P": return .pralltriller
    case "S": return .segno
    case "T": return .trill
    case "u": return .upbow
    case "v": return .downbow
    default:
        return userSymbols[ch] ?? .unknown(String(ch))
    }
}

private func expandLong(_ text: String) -> Decoration {
    switch text {
    // Dynamics
    case "ppp":              return .ppp
    case "pp":               return .pp
    case "p":                return .p
    case "mp":               return .mp
    case "mf":               return .mf
    case "f":                return .f
    case "ff":               return .ff
    case "fff":              return .fff
    case "sfz":              return .sfz
    // Articulations
    case "staccato":         return .staccato
    case "staccatissimo":    return .staccatissimo
    case "tenuto":           return .tenuto
    case "accent":           return .accent
    case ">":                return .strongAccent
    case "arpeggio":         return .arpeggio
    // Ornaments
    case "trill":            return .trill
    case "trill(":           return .trillStart
    case "trill)":           return .trillEnd
    case "mordent":          return .mordent
    case "pralltriller":     return .pralltriller
    case "roll":             return .roll
    case "turn":             return .turn
    case "invertedturn":     return .invertedTurn
    // Fermatas
    case "fermata":          return .fermata
    case "invertedfermata":  return .invertedFermata
    // Bowing
    case "upbow":            return .upbow
    case "downbow":          return .downbow
    case "open":             return .open
    case "snap":             return .snap
    case "thumb":            return .thumb
    case "+":                return .plus
    // Fingering
    case "0": return .fingering(0)
    case "1": return .fingering(1)
    case "2": return .fingering(2)
    case "3": return .fingering(3)
    case "4": return .fingering(4)
    case "5": return .fingering(5)
    // Hairpins
    case "<(":               return .crescendoStart
    case "<)":               return .crescendoEnd
    case ">(":               return .decrescendoStart
    case ">)":               return .decrescendoEnd
    // Navigation
    case "segno":            return .segno
    case "coda":             return .coda
    case "fine":             return .fine
    case "D.C.":             return .dacapo
    case "D.C.al Fine":      return .dacapoAlFine
    case "D.C.al Coda":      return .dacapoAlCoda
    case "D.S.":             return .dalsegno
    case "D.S.al Fine":      return .dalsegnoAlFine
    case "D.S.al Coda":      return .dalsegnoAlCoda
    // Breath
    case "breath":           return .breath
    case "caesura":          return .caesura
    default:                 return .unknown(text)
    }
}
