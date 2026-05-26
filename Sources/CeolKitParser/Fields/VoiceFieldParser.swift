import CeolKitModel

enum VoiceFieldParser {
    static func parse(payload: String, source: SourceRange) -> (id: String, VoiceProperties, [Diagnostic]) {
        var lex = FieldLexer(payload.trimmingCharacters(in: .whitespaces))

        // First token is the voice id
        let id = lex.scanWord() ?? "1"
        lex.skipWhitespace()

        var clef: Clef = .treble
        var octaveShift = 0
        var name: String? = nil
        var subname: String? = nil
        var stem: StemDirection = .auto
        var staffLines = 5
        var transposeSemitones = 0
        var transposeOctave = 0
        var diagnostics: [Diagnostic] = []

        // key=value pairs
        while !lex.isAtEnd {
            guard let key = lex.scanIdentifier() else { lex.advance(); continue }
            lex.skipWhitespace()
            guard lex.consume("=") else { lex.skipWhitespace(); continue }

            switch key.lowercased() {
            case "name", "nm":
                name = lex.current == "\"" ? lex.scanQuotedString() : lex.scanWord()
            case "sname", "snm":
                subname = lex.current == "\"" ? lex.scanQuotedString() : lex.scanWord()
            case "clef":
                if let s = lex.scanWord() {
                    let (c, shift) = KeyFieldParser.parseClefSpec(s)
                    clef = c; octaveShift = shift
                }
            case "stem":
                switch lex.scanWord()?.lowercased() {
                case "up":   stem = .up
                case "down": stem = .down
                default:     stem = .auto
                }
            case "transpose":
                lex.skipWhitespace()
                var sign = 1
                if lex.consume("-") { sign = -1 } else { _ = lex.consume("+") }
                if let n = lex.scanInt() { transposeSemitones = sign * n }
            case "octave":
                lex.skipWhitespace()
                var sign = 1
                if lex.consume("-") { sign = -1 } else { _ = lex.consume("+") }
                if let n = lex.scanInt() { transposeOctave = sign * n }
            case "stafflines":
                if let n = lex.scanInt() { staffLines = n }
            default:
                _ = lex.scanWord()
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: .unknownKey,
                    message: "Unknown V: key '\(key)'",
                    source: source
                ))
            }
            lex.skipWhitespace()
        }

        let props = VoiceProperties(
            clef: ClefSpec(clef: clef, octaveShift: octaveShift),
            transposition: Transposition(semitones: transposeSemitones, octave: transposeOctave),
            staffProperties: StaffProperties(staffLines: staffLines, scale: nil),
            name: name,
            subname: subname,
            stemDirection: stem,
            middleNote: nil
        )
        return (id: id, props, diagnostics)
    }
}
