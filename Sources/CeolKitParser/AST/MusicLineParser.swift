import CeolKitModel

struct MusicLineParser {
    let text: String
    let lineRange: SourceRange

    func parse() -> ([MusicElement], [Diagnostic]) {
        var lexer = MusicLexer(text: text, lineRange: lineRange)
        let tokens = lexer.tokenize()
        var ctx = ParseContext(tokens: tokens)
        return ctx.parseAll()
    }
}

// MARK: - ParseContext

private struct ParseContext {
    let tokens: [(Token, SourceRange)]
    var pos: Int = 0
    var diagnostics: [Diagnostic] = []

    var current: (Token, SourceRange)? {
        pos < tokens.count ? tokens[pos] : nil
    }
    var currentToken: Token? { current?.0 }
    var currentSource: SourceRange? { current?.1 }

    @discardableResult
    mutating func advance() -> (Token, SourceRange)? {
        guard pos < tokens.count else { return nil }
        defer { pos += 1 }
        return tokens[pos]
    }

    mutating func parseAll() -> ([MusicElement], [Diagnostic]) {
        var elements: [MusicElement] = []
        while pos < tokens.count {
            if let elem = parseNext() {
                elements.append(elem)
            }
        }
        return (elements, diagnostics)
    }

    // MARK: Top-level dispatch

    mutating func parseNext() -> MusicElement? {
        guard let (token, source) = current else { return nil }

        switch token {
        // Accidental — must be followed by a pitch letter.
        case .sharp, .doubleSharp, .flat, .doubleFlat, .natural, .microtonalAccidental:
            advance()
            guard let (nextTok, _) = current, case .pitchLetter(let ch) = nextTok else {
                diagnostics.append(reservedDiag("Accidental without pitch letter", source))
                return nil
            }
            advance()
            return parseNoteBody(pitchLetter: ch, accidental: tokenToAccidental(token), startSource: source)

        case .pitchLetter(let ch):
            advance()
            return parseNoteBody(pitchLetter: ch, accidental: nil, startSource: source)

        case .restNormal, .restInvisible, .restFullMeasure, .restFullMeasureInvisible:
            advance()
            let duration = parseDuration()
            return .rest(kind: restKind(token), duration: duration, source: source)

        case .barSingle:     advance(); return .barLine(kind: .single,      source: source)
        case .barDouble:     advance(); return .barLine(kind: .double,      source: source)
        case .barFinal:      advance(); return .barLine(kind: .final,       source: source)
        case .barSectionStart: advance(); return .barLine(kind: .start,    source: source)
        case .barRepeatStart:  advance(); return .barLine(kind: .repeatStart, source: source)
        case .barRepeatEnd:    advance(); return .barLine(kind: .repeatEnd,   source: source)
        case .barRepeatBoth:   advance(); return .barLine(kind: .repeatBoth,  source: source)

        case .endingNumber(let nums):
            advance(); return .endingNumber(nums, source: source)

        case .tupletSpec(let p, let q, let r):
            advance(); return .tupletStart(p: p, q: q, r: r, source: source)

        case .leftBrace:      advance(); return .graceStart(acciaccatura: false, source: source)
        case .leftBraceSlash: advance(); return .graceStart(acciaccatura: true,  source: source)
        case .rightBrace:     advance(); return .graceEnd(source: source)
        case .leftParen:      advance(); return .slurOpen(source: source)
        case .rightParen:     advance(); return .slurClose(source: source)

        case .leftBracket:
            advance()
            return parseChord(openSource: source)

        case .decorationOpen:
            advance()
            return parseDecorationLong(openSource: source)

        case .shortDecoration(let ch):
            advance(); return .decoration(.shortForm(ch), source: source)

        case .quotedString(let s):
            advance(); return parseAnnotationOrChord(s, source: source)

        case .inlineField(let code, let payload):
            advance()
            let (field, diags) = parseField(code: code, payload: payload, source: source)
            diagnostics += diags
            return .inlineField(field, source: source)

        case .space:
            advance(); return .space(source: source)

        case .brokenRight: return parseBrokenRhythm(direction: .right)
        case .brokenLeft:  return parseBrokenRhythm(direction: .left)

        case .unknown(let ch):
            advance()
            diagnostics.append(reservedDiag("Unrecognised character '\(ch)'", source))
            return .unknown(ch, source: source)

        case .integer(let n):
            // Standalone integer at top level = ending number (e.g., :|2 → barRepeatEnd + integer(2))
            advance(); return .endingNumber([n], source: source)

        // Tokens that appear only inside sub-constructs; skip at top level.
        case .tie, .backslash, .decorationClose, .rightBracket,
             .octaveUp, .octaveDown, .slash:
            advance()
            return nil
        }
    }

    // MARK: Note

    mutating func parseNoteBody(
        pitchLetter: Character,
        accidental: AccidentalToken?,
        startSource: SourceRange
    ) -> MusicElement {
        var octaveMarks = 0
        octaveLoop: while let t = currentToken {
            switch t {
            case .octaveUp:   octaveMarks += 1; advance()
            case .octaveDown: octaveMarks -= 1; advance()
            default: break octaveLoop
            }
        }

        let duration = parseDuration()

        var hasTie = false
        if let t = currentToken, case .tie = t { hasTie = true; advance() }

        return .note(NoteToken(
            accidental: accidental,
            pitchLetter: pitchLetter,
            octaveMarks: octaveMarks,
            duration: duration,
            tie: hasTie,
            source: startSource
        ))
    }

    // MARK: Duration
    // Rules:
    //   C     → 1/1   (no integer, no slash)
    //   C2    → 2/1   (integer, no slash)
    //   C/    → 1/2   (no integer, one slash, no integer after)
    //   C/2   → 1/2   (no integer, one slash, integer 2)
    //   C//   → 1/4   (no integer, two slashes)
    //   C3/2  → 3/2   (integer 3, slash, integer 2)

    mutating func parseDuration() -> DurationToken {
        var numerator = 1
        var denominator = 1

        if let t = currentToken, case .integer(let n) = t {
            numerator = n; advance()
        }

        if let t = currentToken, case .slash = t {
            advance()
            if let t2 = currentToken, case .slash = t2 {
                // Two or more slashes: each doubles the denominator.
                denominator = 4; advance()
                while let t3 = currentToken, case .slash = t3 { denominator *= 2; advance() }
            } else if let t2 = currentToken, case .integer(let d) = t2 {
                denominator = d; advance()
            } else {
                denominator = 2
            }
        }

        return DurationToken(numerator: numerator, denominator: denominator)
    }

    // MARK: Chord  ([notes] duration? tie?)

    mutating func parseChord(openSource: SourceRange) -> MusicElement {
        var innerNotes: [NoteToken] = []

        while let (tok, src) = current {
            guard case .rightBracket = tok else {
                innerNotes.append(contentsOf: parseChordNote(tok, src))
                continue
            }
            advance()   // consume ]
            break
        }

        let chordDuration = parseDuration()
        var chordTie = false
        if let t = currentToken, case .tie = t { chordTie = true; advance() }

        // Apply the post-] duration to all inner notes (multiply).
        let chordIsDefault = chordDuration.numerator == 1 && chordDuration.denominator == 1
        let finalNotes = innerNotes.map { note -> NoteToken in
            let newDur: DurationToken
            if chordIsDefault {
                newDur = note.duration
            } else {
                newDur = DurationToken(
                    numerator:   note.duration.numerator   * chordDuration.numerator,
                    denominator: note.duration.denominator * chordDuration.denominator
                )
            }
            return NoteToken(
                accidental: note.accidental,
                pitchLetter: note.pitchLetter,
                octaveMarks: note.octaveMarks,
                duration: newDur,
                tie: note.tie || chordTie,
                source: note.source
            )
        }

        return .chord(finalNotes, source: openSource)
    }

    // Parses one note inside a chord bracket, advancing past it.
    // Returns either one NoteToken wrapped in an array, or empty on parse error.
    mutating func parseChordNote(_ tok: Token, _ src: SourceRange) -> [NoteToken] {
        var accidental: AccidentalToken? = nil
        var noteStart = src
        var pitchChar: Character

        switch tok {
        case .sharp, .doubleSharp, .flat, .doubleFlat, .natural, .microtonalAccidental:
            accidental = tokenToAccidental(tok)
            noteStart = src
            advance()
            guard let (nextTok, _) = current, case .pitchLetter(let ch) = nextTok else {
                advance()  // skip whatever is here
                return []
            }
            pitchChar = ch; advance()

        case .pitchLetter(let ch):
            pitchChar = ch; advance()

        default:
            advance()   // unknown token inside chord — skip
            return []
        }

        var octaveMarks = 0
        octaveLoop: while let t = currentToken {
            switch t {
            case .octaveUp:   octaveMarks += 1; advance()
            case .octaveDown: octaveMarks -= 1; advance()
            default: break octaveLoop
            }
        }

        let dur = parseDuration()

        var hasTie = false
        if let t = currentToken, case .tie = t { hasTie = true; advance() }

        return [NoteToken(
            accidental: accidental,
            pitchLetter: pitchChar,
            octaveMarks: octaveMarks,
            duration: dur,
            tie: hasTie,
            source: noteStart
        )]
    }

    // MARK: Long-form decoration  !text!

    mutating func parseDecorationLong(openSource: SourceRange) -> MusicElement {
        var text = ""
        while let (tok, _) = current {
            if case .decorationClose = tok { advance(); break }
            text += spellingOf(tok)
            advance()
        }
        return .decoration(.longForm(text), source: openSource)
    }

    // Reconstruct source spelling from a token, used to recover decoration text.
    func spellingOf(_ token: Token) -> String {
        switch token {
        case .unknown(let ch):          return String(ch)
        case .pitchLetter(let ch):      return String(ch)
        case .integer(let n):           return String(n)
        case .slash:                    return "/"
        case .sharp:                    return "^"
        case .doubleSharp:              return "^^"
        case .flat:                     return "_"
        case .doubleFlat:               return "__"
        case .natural:                  return "="
        case .space:                    return " "
        case .tie:                      return "-"
        case .octaveUp:                 return "'"
        case .octaveDown:               return ","
        case .brokenRight:              return ">"
        case .brokenLeft:               return "<"
        case .leftParen:                return "("
        case .rightParen:               return ")"
        case .leftBracket:              return "["
        case .rightBracket:             return "]"
        case .leftBrace:                return "{"
        case .rightBrace:               return "}"
        case .leftBraceSlash:           return "{/"
        case .barSingle:                return "|"
        case .barDouble:                return "||"
        case .barFinal:                 return "|]"
        case .barSectionStart:          return "[|"
        case .barRepeatStart:           return "|:"
        case .barRepeatEnd:             return ":|"
        case .barRepeatBoth:            return "::"
        case .shortDecoration(let ch):  return String(ch)
        case .restNormal:               return "z"
        case .restInvisible:            return "x"
        case .restFullMeasure:          return "Z"
        case .restFullMeasureInvisible: return "X"
        case .backslash:                return "\\"
        default:                        return ""
        }
    }

    // MARK: Annotation / chord symbol

    func parseAnnotationOrChord(_ s: String, source: SourceRange) -> MusicElement {
        guard let first = s.first else { return .chordSymbol("", source: source) }
        let rest = String(s.dropFirst())
        switch first {
        case "^": return .annotation(.above, rest, source: source)
        case "_": return .annotation(.below, rest, source: source)
        case "<": return .annotation(.left,  rest, source: source)
        case ">": return .annotation(.right, rest, source: source)
        case "@": return parseAbsoluteAnnotation(rest, source: source)
        default:  return .chordSymbol(s, source: source)
        }
    }

    func parseAbsoluteAnnotation(_ s: String, source: SourceRange) -> MusicElement {
        // Format: "x,y text" (coordinates in staff spaces, optional text after space)
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        if let coordPart = parts.first {
            let xy = coordPart.split(separator: ",")
            if xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) {
                let text = parts.count > 1 ? String(parts[1]) : ""
                return .annotation(.absolute(x: x, y: y), text, source: source)
            }
        }
        return .annotation(.absolute(x: 0, y: 0), s, source: source)
    }

    // MARK: Broken rhythm

    mutating func parseBrokenRhythm(direction: BrokenDirection) -> MusicElement {
        let src = currentSource!
        advance()
        var count = 1
        if direction == .right {
            while let t = currentToken, case .brokenRight = t { count += 1; advance() }
        } else {
            while let t = currentToken, case .brokenLeft  = t { count += 1; advance() }
        }
        return .brokenRhythm(count: count, direction: direction, source: src)
    }

    // MARK: Helpers

    func tokenToAccidental(_ token: Token) -> AccidentalToken? {
        switch token {
        case .sharp:   return .sharp
        case .doubleSharp: return .doubleSharp
        case .flat:    return .flat
        case .doubleFlat:  return .doubleFlat
        case .natural: return .natural
        case .microtonalAccidental(let sign, let num, let den):
            return .microtonal(sign: sign, numerator: num, denominator: den)
        default: return nil
        }
    }

    func restKind(_ token: Token) -> RestKind {
        switch token {
        case .restNormal:               return .normal
        case .restInvisible:            return .invisible
        case .restFullMeasure:          return .fullMeasure
        case .restFullMeasureInvisible: return .fullMeasureInvisible
        default:                        return .normal
        }
    }

    func reservedDiag(_ msg: String, _ source: SourceRange) -> Diagnostic {
        Diagnostic(severity: .warning, code: .reservedCharacter,
                   message: msg, source: source, related: [], hint: nil)
    }
}
