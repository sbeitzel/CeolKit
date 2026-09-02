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
        var middleNote: Pitch? = nil
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
            case "middle", "m":
                // A note in ABC pitch notation, so `middle=B` and `middle=d` are an octave
                // apart and both say something the clef alone does not.
                if let word = lex.scanWord() {
                    if let pitch = parseMiddle(word) {
                        middleNote = pitch
                    } else {
                        diagnostics.append(Diagnostic(
                            severity: .warning,
                            code: .malformedFieldPayload,
                            message: "V: middle= expects a note, not '\(word)'",
                            source: source
                        ))
                    }
                }
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
            staffProperties: StaffProperties(staffLines: staffLines),
            name: name,
            subname: subname,
            stemDirection: stem,
            middleNote: middleNote
        )
        return (id: id, props, diagnostics)
    }

    /// A `middle=` value read as an ABC pitch: an optional accidental, a letter, and octave
    /// marks.  `C` is middle C, `c` the octave above it, `,` and `'` shift by an octave each.
    ///
    /// The accidental is kept because the value is a pitch and a pitch may be altered, but
    /// nothing reads it yet: every use so far — the staff line the clef centres on, the split
    /// a floating voice is assigned by (#80) — is a question about staff position, which is
    /// diatonic.
    private static func parseMiddle(_ text: String) -> Pitch? {
        var rest = Substring(text)

        var alteration = Alteration.natural
        var accidentals = 0
        while let ch = rest.first, ch == "^" || ch == "_" || ch == "=" {
            switch ch {
            case "^": accidentals += 1
            case "_": accidentals -= 1
            default:  accidentals = 0
            }
            rest = rest.dropFirst()
        }
        if accidentals != 0 { alteration = Alteration(numerator: accidentals, denominator: 1) }

        guard let letter = rest.first, let step = diatonicStep(from: letter) else { return nil }
        var octave = letter.isLowercase ? 5 : 4
        rest = rest.dropFirst()

        for ch in rest {
            switch ch {
            case ",":  octave -= 1
            case "'":  octave += 1
            default:   return nil
            }
        }
        return Pitch(step: step, alteration: alteration, octave: octave)
    }
}
