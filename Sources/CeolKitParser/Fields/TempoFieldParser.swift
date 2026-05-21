import CeolKitModel

enum TempoFieldParser {
    static func parse(payload: String, source: SourceRange) -> (Tempo, [Diagnostic]) {
        var lex = FieldLexer(payload.trimmingCharacters(in: .whitespaces))
        var diags: [Diagnostic] = []

        // Optional prelude text
        var prelude: TextString? = nil
        if let q = lex.scanQuotedString() {
            prelude = TextString(value: q, source: source)
            lex.skipWhitespace()
        }

        var beats: [Fraction] = []
        var bpm = 120.0

        if String(lex.remaining).contains("=") {
            // Format: beat1 beat2 ... = bpm
            while let frac = lex.scanFraction() {
                beats.append(Fraction(numerator: frac.numerator, denominator: frac.denominator))
                lex.skipWhitespace()
                if lex.current == "=" { break }
            }
            if lex.consume("=") {
                lex.skipWhitespace()
                if let n = lex.scanInt() {
                    bpm = Double(n)
                } else {
                    diags.append(malformed("Expected BPM after '=' in tempo: '\(payload)'", source))
                }
            } else {
                diags.append(malformed("Expected '=' in tempo: '\(payload)'", source))
            }
        } else {
            // Format: bpm (plain integer, defaults to quarter = bpm)
            if let n = lex.scanInt() {
                bpm = Double(n)
                beats = [Fraction(numerator: 1, denominator: 4)]
            } else {
                diags.append(malformed("Cannot parse tempo: '\(payload)'", source))
            }
        }

        // Optional postlude text
        lex.skipWhitespace()
        var postlude: TextString? = nil
        if let q = lex.scanQuotedString() {
            postlude = TextString(value: q, source: source)
        }

        return (Tempo(prelude: prelude, beats: beats, bpm: bpm, postlude: postlude), diags)
    }
}

private func malformed(_ msg: String, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .malformedFieldPayload, message: msg,
               source: source, related: [], hint: nil)
}
