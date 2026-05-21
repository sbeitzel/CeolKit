import CeolKitModel

enum LengthFieldParser {
    static func parse(payload: String, source: SourceRange) -> (Fraction, [Diagnostic]) {
        var lex = FieldLexer(payload.trimmingCharacters(in: .whitespaces))
        if let frac = lex.scanFraction() {
            return (Fraction(numerator: frac.numerator, denominator: frac.denominator), [])
        }
        return (
            Fraction(numerator: 1, denominator: 8),
            [Diagnostic(severity: .warning, code: .malformedFieldPayload,
                        message: "Malformed unit note length: '\(payload)'",
                        source: source, related: [], hint: nil)]
        )
    }
}
