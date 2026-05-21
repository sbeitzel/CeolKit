import CeolKitModel

enum LyricParser {
    // Parses a w: payload into LyricTokens.
    //
    // Tokenisation rules (character-by-character):
    //  space   → end of current syllable (wordEnd)
    //  -       → end of current syllable with hyphen connection (mid-word)
    //  |       → flush current syllable (wordEnd), emit barReset
    //  _       → flush current syllable (wordEnd) if non-empty, emit melisma
    //  *       → flush current syllable (wordEnd) if non-empty, emit skip
    //  ~       → stays in syllable text (word-linking space; rendered as no-break)
    //  other   → accumulate into current syllable
    static func parse(payload: String, source: SourceRange) -> ([LyricToken], [Diagnostic]) {
        var tokens: [LyricToken] = []
        var current = ""

        for ch in payload {
            switch ch {
            case " ":
                if !current.isEmpty {
                    tokens.append(.syllable(current, connection: .wordEnd))
                    current = ""
                }
            case "-":
                tokens.append(.syllable(current, connection: .hyphen))
                current = ""
            case "|":
                if !current.isEmpty {
                    tokens.append(.syllable(current, connection: .wordEnd))
                    current = ""
                }
                tokens.append(.barReset)
            case "_":
                if !current.isEmpty {
                    tokens.append(.syllable(current, connection: .wordEnd))
                    current = ""
                }
                tokens.append(.melisma)
            case "*":
                if !current.isEmpty {
                    tokens.append(.syllable(current, connection: .wordEnd))
                    current = ""
                }
                tokens.append(.skip)
            default:
                current.append(ch)
            }
        }

        if !current.isEmpty {
            tokens.append(.syllable(current, connection: .wordEnd))
        }

        return (tokens, [])
    }
}
