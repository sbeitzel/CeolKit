import CeolKitModel

enum MeterFieldParser {
    static func parse(payload: String, source: SourceRange) -> (Meter, [Diagnostic]) {
        let t = payload.trimmingCharacters(in: .whitespaces)

        if t == "C"  { return (.commonTime, []) }
        if t == "C|" { return (.cutTime, []) }
        if t.lowercased() == "none" { return (.free, []) }

        // Complex: (n+m+...)/d
        if t.hasPrefix("(") {
            if let meter = parseComplex(t) { return (meter, []) }
            return (.fraction(num: 4, den: 4), [malformed("Malformed complex meter: '\(payload)'", source)])
        }

        // Simple fraction: n/d
        var lex = FieldLexer(t)
        if let num = lex.scanInt(), lex.consume("/"), let den = lex.scanInt() {
            return (.fraction(num: num, den: den), [])
        }

        return (.fraction(num: 4, den: 4), [malformed("Malformed meter: '\(payload)'", source)])
    }

    private static func parseComplex(_ t: String) -> Meter? {
        var rest = t.dropFirst()  // drop '('
        var groups: [Int] = []
        while true {
            var numStr = ""
            while let c = rest.first, c.isNumber { numStr.append(c); rest = rest.dropFirst() }
            guard let n = Int(numStr) else { break }
            groups.append(n)
            if rest.first == "+" { rest = rest.dropFirst() } else { break }
        }
        if rest.first == ")" { rest = rest.dropFirst() }
        if rest.first == "/" { rest = rest.dropFirst() }
        var denStr = ""
        while let c = rest.first, c.isNumber { denStr.append(c); rest = rest.dropFirst() }
        guard !groups.isEmpty, let den = Int(denStr) else { return nil }
        return .complex(groups, den: den)
    }
}

private func malformed(_ msg: String, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .malformedFieldPayload, message: msg,
               source: source, related: [], hint: nil)
}
