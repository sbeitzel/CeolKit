struct FieldLexer {
    let source: String
    private(set) var pos: String.Index
    private(set) var byteOffset: Int

    init(_ source: String) {
        self.source = source
        self.pos = source.startIndex
        self.byteOffset = 0
    }

    var isAtEnd: Bool { pos >= source.endIndex }

    var current: Character? {
        guard pos < source.endIndex else { return nil }
        return source[pos]
    }

    func peek(offset: Int = 1) -> Character? {
        var idx = pos
        for _ in 0..<offset {
            guard idx < source.endIndex else { return nil }
            idx = source.index(after: idx)
        }
        guard idx < source.endIndex else { return nil }
        return source[idx]
    }

    var remaining: Substring { source[pos...] }

    @discardableResult
    mutating func advance() -> Character? {
        guard pos < source.endIndex else { return nil }
        let ch = source[pos]
        byteOffset += ch.utf8.count
        pos = source.index(after: pos)
        return ch
    }

    mutating func consume(_ ch: Character) -> Bool {
        guard current == ch else { return false }
        advance()
        return true
    }

    mutating func skipWhitespace() {
        while let ch = current, ch.isWhitespace { advance() }
    }

    // Returns nil if current is not a digit.
    mutating func scanInt() -> Int? {
        guard current?.isNumber == true else { return nil }
        var value = 0
        while let d = current, d.isNumber, let v = d.wholeNumberValue {
            value = value * 10 + v
            advance()
        }
        return value
    }

    // Parses n/d; returns nil if no integer found.
    mutating func scanFraction() -> (numerator: Int, denominator: Int)? {
        guard let num = scanInt() else { return nil }
        guard consume("/") else { return (num, 1) }
        let den = scanInt() ?? 1
        return (num, den)
    }

    // Scans a run of non-whitespace characters.
    mutating func scanWord() -> String? {
        guard let first = current, !first.isWhitespace else { return nil }
        var result = ""
        while let ch = current, !ch.isWhitespace {
            result.append(ch)
            advance()
        }
        return result.isEmpty ? nil : result
    }

    // Scans an alphanumeric identifier (letters and digits only).
    mutating func scanIdentifier() -> String? {
        guard let first = current, first.isLetter else { return nil }
        var result = ""
        while let ch = current, ch.isLetter || ch.isNumber {
            result.append(ch)
            advance()
        }
        return result.isEmpty ? nil : result
    }

    // Scans "quoted content"; returns nil if opening " is absent.
    mutating func scanQuotedString() -> String? {
        guard consume("\"") else { return nil }
        var result = ""
        while let ch = current, ch != "\"" {
            result.append(ch)
            advance()
        }
        _ = consume("\"")
        return result
    }
}
