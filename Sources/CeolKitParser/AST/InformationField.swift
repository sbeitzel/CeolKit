import CeolKitModel

// Parser-layer lyric token, produced by LyricParser from a w: field payload.
// The semantic pass (LyricAligner) maps these to per-note LyricSyllable values.
enum LyricToken {
    case syllable(String, connection: LyricConnection)
    case melisma    // _
    case skip       // *
    case barReset   // |
}

enum InformationField {
    case referenceNumber(Int, source: SourceRange)
    case title(TextString)
    case key(KeySignature)
    case meter(Meter, source: SourceRange)
    case unitNoteLength(Fraction, source: SourceRange)
    case tempo(Tempo, source: SourceRange)
    case voice(id: String, properties: VoiceProperties, source: SourceRange)
    case lyric([LyricToken], source: SourceRange)           // w:
    case words(TextString)                                   // W:
    case composer(TextString)
    case origin(TextString)
    case area(TextString)
    case book(TextString)
    case discography(TextString)
    case fileUrl(TextString)
    case group(TextString)
    case history(TextString)
    case instruction(TextString)                            // I:
    case notes(TextString)
    case sourceText(TextString)                             // S:
    case rhythm(TextString)
    case transcription(TextString)                          // Z:
    case userSymbol(Character, Decoration, source: SourceRange)  // U:
    case parts(PartPlan)                                    // P:
    case macro(String, String, source: SourceRange)         // m: pattern = expansion (v0.2 stub)
    case unknown(code: Character, payload: String, source: SourceRange)

    var source: SourceRange {
        switch self {
        case .referenceNumber(_, let s):        return s
        case .title(let t):                     return t.source
        case .key(let k):                       return k.source
        case .meter(_, let s):                  return s
        case .unitNoteLength(_, let s):         return s
        case .tempo(_, let s):                  return s
        case .voice(_, _, let s):               return s
        case .lyric(_, let s):                  return s
        case .words(let t):                     return t.source
        case .composer(let t):                  return t.source
        case .origin(let t):                    return t.source
        case .area(let t):                      return t.source
        case .book(let t):                      return t.source
        case .discography(let t):               return t.source
        case .fileUrl(let t):                   return t.source
        case .group(let t):                     return t.source
        case .history(let t):                   return t.source
        case .instruction(let t):               return t.source
        case .notes(let t):                     return t.source
        case .sourceText(let t):                return t.source
        case .rhythm(let t):                    return t.source
        case .transcription(let t):             return t.source
        case .userSymbol(_, _, let s):          return s
        case .parts(let p):                     return p.source
        case .macro(_, _, let s):               return s
        case .unknown(_, _, let s):             return s
        }
    }
}
