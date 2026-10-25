import CeolKitModel

/// What a stretch of ABC source is, for an editor coloring it (#229).
public enum HighlightKind: String, Sendable, CaseIterable {
    case comment                  // % …
    case directive                // %%name payload
    case versionLine              // %abc-2.1
    case fieldKey                 // T:
    case fieldValue               // the payload after it
    case inlineField              // [K:G]
    case barLine                  // | || |] [| |: :| ::
    case ending                   // |1  [2  :|1,3
    case note                     // pitch letters, octave marks, chord brackets
    case rest                     // z x Z X
    case accidental               // ^ ^^ _ __ = ^3/4
    case duration                 // 2 /2 3/2 > <
    case chordSymbol              // "G7"
    case annotation               // "^text" "_text" "<text" ">text" "@text"
    case decoration               // !trill! . ~ H L M O P S T u v
    case graceNote                // { } {/
    case slurTieTuplet            // ( ) - (3
    case freeText                 // text outside any tune
}

/// One colored stretch of source.
public struct HighlightSpan: Sendable, Equatable {
    public let kind: HighlightKind
    public let range: SourceRange

    public init(kind: HighlightKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }
}

public extension CeolKitParser {
    /// Classifies `source` for syntax coloring, using the same line classifier and lexer
    /// the parser reads it with, so an editor colors text the way CeolKit understands it.
    ///
    /// Spans are in source order and never overlap; text no span covers (spaces, unknown
    /// characters) is left uncolored.  Ranges count UTF-8 bytes into `source` with CRLF
    /// normalized to LF, like every other ``SourceRange`` the parser makes.  Includes are
    /// not expanded: an `I:abc-include` line is an ordinary field.
    static func highlightSpans(in source: String) -> [HighlightSpan] {
        Highlighter(source: Source(content: source, fileName: nil)).spans()
    }
}

struct Highlighter {
    let source: Source

    func spans() -> [HighlightSpan] {
        var result: [HighlightSpan] = []
        let lines = LineClassifier(source: source, dialectHint: nil).classifyPhysicalLines()
        for (line, (_, text, _)) in zip(lines, source.lines()) {
            switch line {
            case .empty:
                break
            case .comment(_, let range):
                result.append(HighlightSpan(kind: .comment, range: range))
            case .versionLine(_, let range):
                result.append(HighlightSpan(kind: .versionLine, range: range))
            case .directive(_, _, let range):
                result.append(HighlightSpan(kind: .directive, range: range))
            case .freeText(_, let range):
                result.append(HighlightSpan(kind: .freeText, range: range))
            case .informationField(let code, _, let range):
                result += fieldSpans(text, code: code, line: range)
            case .musicLine(_, let range):
                result += musicSpans(text, line: range)
            }
        }
        return Self.merged(result)
    }

    private func fieldSpans(_ text: Substring, code: Character, line: SourceRange) -> [HighlightSpan] {
        let keyLength = code.utf8.count + 1
        let commentStart = Self.commentStart(in: text) ?? text.utf8.count
        var spans = [HighlightSpan(kind: .fieldKey, range: Self.range(in: line, at: 0, length: keyLength))]
        if commentStart > keyLength {
            spans.append(HighlightSpan(kind: .fieldValue,
                                       range: Self.range(in: line, at: keyLength,
                                                         length: commentStart - keyLength)))
        }
        if commentStart < text.utf8.count {
            spans.append(HighlightSpan(kind: .comment,
                                       range: Self.range(in: line, at: commentStart,
                                                         length: text.utf8.count - commentStart)))
        }
        return spans
    }

    private func musicSpans(_ text: Substring, line: SourceRange) -> [HighlightSpan] {
        var lexer = MusicLexer(text: String(text), lineRange: line)
        let tokens = lexer.tokenize()
        var spans: [HighlightSpan] = []
        var index = 0
        while index < tokens.count {
            let (token, range) = tokens[index]
            if case .decorationOpen = token {
                // The name between the `!`s lexes as whatever its letters happen to be;
                // the whole `!…!` is one decoration.
                var end = index
                while end + 1 < tokens.count {
                    end += 1
                    if case .decorationClose = tokens[end].0 { break }
                }
                let last = tokens[end].1
                spans.append(HighlightSpan(
                    kind: .decoration,
                    range: Self.range(in: line, at: range.byteOffset - line.byteOffset,
                                      length: last.byteOffset + last.length - range.byteOffset)))
                index = end + 1
                continue
            }
            if let kind = Self.kind(of: token) {
                spans.append(HighlightSpan(kind: kind, range: range))
            }
            index += 1
        }
        // The lexer stops at a `%` outside any quoted string, and only there: whatever it
        // left unread is a trailing comment.
        let consumed = tokens.last.map { $0.1.byteOffset + $0.1.length - line.byteOffset } ?? 0
        if consumed < text.utf8.count {
            spans.append(HighlightSpan(kind: .comment,
                                       range: Self.range(in: line, at: consumed,
                                                         length: text.utf8.count - consumed)))
        }
        return spans
    }

    private static func kind(of token: Token) -> HighlightKind? {
        switch token {
        case .sharp, .doubleSharp, .flat, .doubleFlat, .natural, .microtonalAccidental:
            .accidental
        case .pitchLetter, .octaveUp, .octaveDown, .leftBracket, .rightBracket:
            .note
        case .integer, .slash, .brokenRight, .brokenLeft:
            .duration
        case .barSingle, .barDouble, .barFinal, .barSectionStart, .barRepeatStart,
             .barRepeatEnd, .barRepeatBoth, .barSectionRepeatStart, .barRepeatEndSection:
            .barLine
        case .endingNumber:
            .ending
        case .leftParen, .rightParen, .tie, .tupletSpec:
            .slurTieTuplet
        case .leftBrace, .rightBrace, .leftBraceSlash:
            .graceNote
        case .decorationOpen, .decorationClose, .shortDecoration:
            .decoration
        case .quotedString(let text):
            // §4.19: a leading placement character makes the string an annotation.
            text.first.map { "^_<>@".contains($0) } == true ? .annotation : .chordSymbol
        case .inlineField:
            .inlineField
        case .restNormal, .restInvisible, .restFullMeasure, .restFullMeasureInvisible:
            .rest
        case .space, .backslash, .voiceOverlay, .unknown:
            nil
        }
    }

    /// Byte offset of the first `%` that is not escaped as `\%`, if any.
    private static func commentStart(in text: Substring) -> Int? {
        var offset = 0
        var previous: Character?
        for ch in text {
            if ch == "%" && previous != "\\" { return offset }
            offset += ch.utf8.count
            previous = ch
        }
        return nil
    }

    private static func range(in line: SourceRange, at offset: Int, length: Int) -> SourceRange {
        SourceRange(file: line.file, byteOffset: line.byteOffset + offset, length: length,
                    line: line.line, column: line.column + offset)
    }

    /// Joins spans of one kind that touch, so `^c'2` is an accidental, one note and a
    /// duration rather than a span per token.
    private static func merged(_ spans: [HighlightSpan]) -> [HighlightSpan] {
        var result: [HighlightSpan] = []
        for span in spans {
            if let last = result.last, last.kind == span.kind,
               last.range.byteOffset + last.range.length == span.range.byteOffset,
               last.range.line == span.range.line {
                result[result.count - 1] = HighlightSpan(
                    kind: last.kind,
                    range: SourceRange(file: last.range.file, byteOffset: last.range.byteOffset,
                                       length: last.range.length + span.range.length,
                                       line: last.range.line, column: last.range.column))
            } else {
                result.append(span)
            }
        }
        return result
    }
}
