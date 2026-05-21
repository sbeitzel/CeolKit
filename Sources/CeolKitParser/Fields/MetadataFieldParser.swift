import CeolKitModel
import Foundation

enum MetadataFieldParser {
    static func parse(code: Character, payload: String, source: SourceRange) -> (InformationField, [Diagnostic]) {
        let text = TextString(value: stripComment(payload), source: source)
        switch code {
        case "T": return (.title(text), [])
        case "C": return (.composer(text), [])
        case "O": return (.origin(text), [])
        case "A": return (.area(text), [])
        case "B": return (.book(text), [])
        case "D": return (.discography(text), [])
        case "F": return (.fileUrl(text), [])
        case "G": return (.group(text), [])
        case "H": return (.history(text), [])
        case "I": return (.instruction(text), [])
        case "N": return (.notes(text), [])
        case "S": return (.sourceText(text), [])
        case "R": return (.rhythm(text), [])
        case "Z": return (.transcription(text), [])
        case "W": return (.words(text), [])
        case "U": return parseUserSymbol(payload: payload, source: source)
        case "P": return parseParts(payload: payload, source: source)
        default:  return (.unknown(code: code, payload: payload, source: source), [])
        }
    }

    // MARK: - U: user symbol

    private static func parseUserSymbol(payload: String, source: SourceRange) -> (InformationField, [Diagnostic]) {
        let t = payload.trimmingCharacters(in: .whitespaces)
        guard let char = t.first else {
            return (.unknown(code: "U", payload: payload, source: source),
                    [malformed("Empty U: field", source)])
        }

        // Format: char [=] [!name! | shortChar]
        var rest = Substring(t.dropFirst())
        rest = Substring(rest.drop(while: { $0.isWhitespace }))
        if rest.first == "=" { rest = rest.dropFirst() }
        rest = Substring(rest.drop(while: { $0.isWhitespace }))

        let decoration: Decoration
        if rest.first == "!" {
            rest = rest.dropFirst()
            var name = ""
            while let c = rest.first, c != "!" { name.append(c); rest = rest.dropFirst() }
            decoration = decorationFromName(name)
        } else if let c = rest.first {
            decoration = decorationFromShortForm(c)
        } else {
            decoration = .unknown(String(char))
        }

        return (.userSymbol(char, decoration, source: source), [])
    }

    // MARK: - P: parts

    private static func parseParts(payload: String, source: SourceRange) -> (InformationField, [Diagnostic]) {
        let t = payload.trimmingCharacters(in: .whitespaces)
        var labels: [PartLabel] = []
        var byteIdx = 0
        for ch in t.unicodeScalars {
            if Character(ch).isUppercase, Character(ch).isLetter {
                let labelSrc = SourceRange(
                    file: source.file,
                    byteOffset: source.byteOffset + byteIdx,
                    length: 1,
                    line: source.line,
                    column: source.column + byteIdx
                )
                labels.append(PartLabel(letter: Character(ch), source: labelSrc))
            }
            byteIdx += ch.utf8.count
        }
        let plan = PartPlan(sequence: labels, source: source)
        return (.parts(plan), [])
    }

    // MARK: - Decoration lookup

    static func decorationFromName(_ name: String) -> Decoration {
        switch name.lowercased() {
        case "staccato":                return .staccato
        case "staccatissimo":           return .staccatissimo
        case "tenuto":                  return .tenuto
        case "accent":                  return .accent
        case "strongaccent", ">":       return .strongAccent
        case "arpeggio":                return .arpeggio
        case "trill":                   return .trill
        case "trill(":                  return .trillStart
        case "trill)":                  return .trillEnd
        case "mordent":                 return .mordent
        case "pralltriller":            return .pralltriller
        case "roll":                    return .roll
        case "turn":                    return .turn
        case "invertedturn":            return .invertedTurn
        case "fermata":                 return .fermata
        case "invertedfermata":         return .invertedFermata
        case "upbow":                   return .upbow
        case "downbow":                 return .downbow
        case "open":                    return .open
        case "snap":                    return .snap
        case "thumb":                   return .thumb
        case "+":                       return .plus
        case "0": return .fingering(0); case "1": return .fingering(1)
        case "2": return .fingering(2); case "3": return .fingering(3)
        case "4": return .fingering(4); case "5": return .fingering(5)
        case "<(":                      return .crescendoStart
        case "<)":                      return .crescendoEnd
        case ">(":                      return .decrescendoStart
        case ">)":                      return .decrescendoEnd
        case "segno":                   return .segno
        case "coda":                    return .coda
        case "fine":                    return .fine
        case "d.c.", "d.c":             return .dacapo
        case "d.c.al fine":             return .dacapoAlFine
        case "d.c.al coda":             return .dacapoAlCoda
        case "d.s.", "d.s":             return .dalsegno
        case "d.s.al fine":             return .dalsegnoAlFine
        case "d.s.al coda":             return .dalsegnoAlCoda
        case "breath":                  return .breath
        case "caesura":                 return .caesura
        case "ppp":                     return .ppp
        case "pp":                      return .pp
        case "p":                       return .p
        case "mp":                      return .mp
        case "mf":                      return .mf
        case "f":                       return .f
        case "ff":                      return .ff
        case "fff":                     return .fff
        case "sfz":                     return .sfz
        default:                        return .unknown(name)
        }
    }

    static func decorationFromShortForm(_ ch: Character) -> Decoration {
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
        default:  return .unknown(String(ch))
        }
    }
}

private func stripComment(_ s: String) -> String {
    // Strip inline ABC comment: % starts a comment; strip it and trim whitespace.
    if let idx = s.firstIndex(of: "%") {
        return String(s[..<idx]).trimmingCharacters(in: .whitespaces)
    }
    return s.trimmingCharacters(in: .whitespaces)
}

private func malformed(_ msg: String, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .malformedFieldPayload, message: msg,
               source: source, related: [], hint: nil)
}
