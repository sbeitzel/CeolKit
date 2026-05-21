import CeolKitModel

struct MusicLexer {
    private let text: String
    private let lineRange: SourceRange
    private var pos: String.Index
    private var localOffset: Int
    private var insideDecoration = false

    init(text: String, lineRange: SourceRange) {
        self.text = text
        self.lineRange = lineRange
        self.pos = text.startIndex
        self.localOffset = 0
    }

    mutating func tokenize() -> [(Token, SourceRange)] {
        var result: [(Token, SourceRange)] = []
        while pos < text.endIndex {
            guard let ch = current else { break }
            if ch == "%" { break }  // rest of line is comment
            let startOffset = localOffset
            advance()
            let token = scan(leading: ch)
            let length = max(1, localOffset - startOffset)
            result.append((token, makeRange(at: startOffset, length: length)))
        }
        return result
    }

    // MARK: - Helpers

    private var current: Character? {
        guard pos < text.endIndex else { return nil }
        return text[pos]
    }

    private func peekAt(_ offset: Int) -> Character? {
        var idx = pos
        for _ in 0..<offset {
            guard idx < text.endIndex else { return nil }
            idx = text.index(after: idx)
        }
        guard idx < text.endIndex else { return nil }
        return text[idx]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard pos < text.endIndex else { return nil }
        let ch = text[pos]
        localOffset += ch.utf8.count
        pos = text.index(after: pos)
        return ch
    }

    private func makeRange(at start: Int, length: Int) -> SourceRange {
        SourceRange(
            file: lineRange.file,
            byteOffset: lineRange.byteOffset + start,
            length: length,
            line: lineRange.line,
            column: lineRange.column + start
        )
    }

    // MARK: - Top-level dispatch

    private mutating func scan(leading ch: Character) -> Token {
        switch ch {
        case "^": return scanAccidental(sign: 1, single: .sharp, double: .doubleSharp)
        case "_": return scanAccidental(sign: -1, single: .flat, double: .doubleFlat)
        case "=": return .natural
        case "A", "B", "C", "D", "E", "F", "G",
             "a", "b", "c", "d", "e", "f", "g": return .pitchLetter(ch)
        case "'": return .octaveUp
        case ",": return .octaveDown
        case "z": return .restNormal
        case "x": return .restInvisible
        case "Z": return .restFullMeasure
        case "X": return .restFullMeasureInvisible
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": return scanInteger(first: ch)
        case "/": return .slash
        case "|": return scanPipe()
        case "[": return scanLeftBracket()
        case "]": return .rightBracket
        case "(": return scanLeftParen()
        case ")": return .rightParen
        case "{":
            if current == "/" { advance(); return .leftBraceSlash }
            return .leftBrace
        case "}": return .rightBrace
        case "\"": return scanQuotedString()
        case "!": return scanExclamation()
        case ".": return .shortDecoration(".")
        case "~": return .shortDecoration("~")
        case "H": return .shortDecoration("H")
        case "L": return .shortDecoration("L")
        case "M": return .shortDecoration("M")
        case "O": return .shortDecoration("O")
        case "P": return .shortDecoration("P")
        case "S": return .shortDecoration("S")
        case "T": return .shortDecoration("T")
        case "u": return .shortDecoration("u")
        case "v": return .shortDecoration("v")
        case "-": return .tie
        case ">": return .brokenRight
        case "<": return .brokenLeft
        case ":": return scanColon()
        case " ", "\t": return scanSpace()
        case "\\": return .backslash
        default: return .unknown(ch)
        }
    }

    // MARK: - Sub-scanners

    private mutating func scanAccidental(sign: Int, single: Token, double: Token) -> Token {
        let doubleChar: Character = sign == 1 ? "^" : "_"
        if current == doubleChar { advance(); return double }
        if current?.isNumber == true { return scanMicrotonal(sign: sign) }
        return single
    }

    private mutating func scanMicrotonal(sign: Int) -> Token {
        let num = scanDigits()
        guard current == "/" else {
            return .microtonalAccidental(sign: sign, numerator: num, denominator: 1)
        }
        advance()  // consume /
        let den = current?.isNumber == true ? scanDigits() : 1
        return .microtonalAccidental(sign: sign, numerator: num, denominator: den)
    }

    private mutating func scanDigits() -> Int {
        var value = 0
        while let d = current, d.isNumber, let v = d.wholeNumberValue {
            value = value * 10 + v
            advance()
        }
        return value
    }

    private mutating func scanInteger(first: Character) -> Token {
        var value = first.wholeNumberValue ?? 0
        while let d = current, d.isNumber, let v = d.wholeNumberValue {
            value = value * 10 + v
            advance()
        }
        return .integer(value)
    }

    private mutating func scanPipe() -> Token {
        switch current {
        case "]": advance(); return .barFinal
        case "|": advance(); return .barDouble
        case ":": advance(); return .barRepeatStart
        case let d? where d.isNumber: return scanEndingNumber()
        default: return .barSingle
        }
    }

    private mutating func scanColon() -> Token {
        switch current {
        case "|": advance(); return .barRepeatEnd
        case ":": advance(); return .barRepeatBoth
        default: return .unknown(":")
        }
    }

    private mutating func scanLeftBracket() -> Token {
        if current == "|" { advance(); return .barSectionStart }
        if current?.isNumber == true { return scanEndingNumber() }
        if let letter = current, letter.isLetter, peekAt(1) == ":" {
            advance()  // consume letter
            advance()  // consume :
            let payload = scanUntil("]")
            if current == "]" { advance() }
            return .inlineField(code: letter, payload: payload)
        }
        return .leftBracket
    }

    private mutating func scanEndingNumber() -> Token {
        var numbers: [Int] = []
        outer: while current?.isNumber == true {
            let n = scanDigits()
            if current == "-" {
                advance()  // consume -
                if current?.isNumber == true {
                    let m = scanDigits()
                    if m >= n {
                        for i in n...m { numbers.append(i) }
                    } else {
                        numbers.append(n)
                    }
                } else {
                    numbers.append(n)
                }
            } else {
                numbers.append(n)
            }
            if current == "," { advance() } else { break outer }
        }
        return .endingNumber(numbers.isEmpty ? [1] : numbers)
    }

    private mutating func scanLeftParen() -> Token {
        guard current?.isNumber == true else { return .leftParen }
        let p = scanDigits()
        var q: Int? = nil
        var r: Int? = nil
        if current == ":" {
            advance()
            if current?.isNumber == true { q = scanDigits() }
            if current == ":" {
                advance()
                if current?.isNumber == true { r = scanDigits() }
            }
        }
        return .tupletSpec(p: p, q: q, r: r)
    }

    private mutating func scanQuotedString() -> Token {
        let content = scanUntil("\"")
        if current == "\"" { advance() }
        return .quotedString(content)
    }

    private mutating func scanExclamation() -> Token {
        if insideDecoration {
            insideDecoration = false
            return .decorationClose
        }
        insideDecoration = true
        return .decorationOpen
    }

    private mutating func scanSpace() -> Token {
        while let ch = current, ch == " " || ch == "\t" { advance() }
        return .space
    }

    private mutating func scanUntil(_ terminator: Character) -> String {
        var result = ""
        while let ch = current, ch != terminator {
            result.append(ch)
            advance()
        }
        return result
    }
}
