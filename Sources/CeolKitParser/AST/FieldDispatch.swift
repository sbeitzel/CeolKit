import CeolKitModel

// Shared dispatch for all information-field codes. Called by ABCFileBuilder (whole-line
// fields) and MusicLineParser (inline [X:payload] fields).
func parseField(
    code: Character,
    payload: String,
    source: SourceRange
) -> (InformationField, [Diagnostic]) {
    switch code {
    case "X":
        let t = stripFieldComment(payload).trimmingCharacters(in: .whitespaces)
        if let n = Int(t) { return (.referenceNumber(n, source: source), []) }
        return (
            .unknown(code: code, payload: payload, source: source),
            [malformed("X: value must be an integer: '\(payload)'", source)]
        )

    case "K":
        let (key, diags) = KeyFieldParser.parse(payload: payload, source: source)
        return (.key(key), diags)

    case "M":
        let (meter, diags) = MeterFieldParser.parse(payload: payload, source: source)
        return (.meter(meter, source: source), diags)

    case "L":
        let (frac, diags) = LengthFieldParser.parse(payload: payload, source: source)
        return (.unitNoteLength(frac, source: source), diags)

    case "Q":
        let (tempo, diags) = TempoFieldParser.parse(payload: payload, source: source)
        return (.tempo(tempo, source: source), diags)

    case "V":
        let (id, props, diags) = VoiceFieldParser.parse(payload: payload, source: source)
        return (.voice(id: id, properties: props, source: source), diags)

    case "w":
        let (tokens, diags) = LyricParser.parse(payload: payload, source: source)
        return (.lyric(tokens, source: source), diags)

    case "m":
        let parts = payload.components(separatedBy: "=")
        let pattern = (parts.first ?? "").trimmingCharacters(in: .whitespaces)
        let expansion = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)
        return (.macro(pattern, expansion, source: source), [])

    default:
        let (field, diags) = MetadataFieldParser.parse(code: code, payload: payload, source: source)
        if case .unknown = field {
            return (field, diags + [unknownField(code, source)])
        }
        return (field, diags)
    }
}

private func stripFieldComment(_ s: String) -> String {
    if let idx = s.firstIndex(of: "%") {
        return String(s[..<idx])
    }
    return s
}

private func malformed(_ msg: String, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .malformedFieldPayload, message: msg,
               source: source, related: [], hint: nil)
}

private func unknownField(_ code: Character, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .unknownField,
               message: "Unknown information field '\(code):'",
               source: source, related: [], hint: nil)
}
