import CeolKitModel

struct LineClassifier {
    let source: Source
    let dialectHint: Dialect?

    func classify() -> [LogicalLine] {
        var result: [LogicalLine] = []
        var mode = ParserMode.preamble
        // A music line ended in `\`.  `text` is what has been gathered so far and `source`
        // where it started; `deferred` holds the lines that fell between it and its
        // continuation, which are emitted once the music line is whole again.
        var pendingContinuation: (text: String, source: SourceRange, deferred: [LogicalLine])? = nil

        for (lineNumber, text, _) in source.lines() {
            let str = String(text)
            let lineSource = source.range(line: lineNumber, column: 1, length: text.utf8.count)
            let line = classifyLine(str, source: lineSource, mode: mode)

            // §2.2: a backslash continues a music line *through* information fields,
            // comments and stylesheet directives — only the next line of music code joins
            // it.  Anything else is set aside and emitted after the music line it
            // interrupted, so a `w:` still lands on the line it belongs to.  Comments are
            // dropped, as they are everywhere else.
            if var cont = pendingContinuation {
                switch line {
                case .musicLine(let t, _):
                    if t.hasSuffix("\\") {
                        cont.text += String(t.dropLast())
                        pendingContinuation = cont
                    } else {
                        cont.text += t
                        result.append(.musicLine(text: cont.text, source: cont.source))
                        result += cont.deferred
                        pendingContinuation = nil
                    }
                    continue
                case .comment:
                    continue
                case .empty:
                    // Illegal per §6.1.1 — a backslash must not precede an empty line.
                    // Flush what there is rather than swallow the rest of the tune.
                    result.append(.musicLine(text: cont.text, source: cont.source))
                    result += cont.deferred
                    pendingContinuation = nil
                default:
                    cont.deferred.append(line)
                    pendingContinuation = cont
                    continue
                }
            }

            // Update state machine
            switch line {
            case .empty:
                if case .body = mode { mode = .preamble }
            case .informationField(let code, _, _):
                switch mode {
                case .preamble where code == "X": mode = .header
                case .preamble where code == "K": mode = .body  // recovery: no X: preceding K:
                case .header where code == "K": mode = .body
                default: break
                }
            default:
                break
            }

            // Start continuation tracking for music lines ending with backslash.
            if case .musicLine(let t, let s) = line, t.hasSuffix("\\") {
                pendingContinuation = (text: String(t.dropLast()), source: s, deferred: [])
                continue
            }

            result.append(line)
        }

        // Flush dangling continuation.
        if let cont = pendingContinuation {
            result.append(.musicLine(text: cont.text, source: cont.source))
            result += cont.deferred
        }

        return result
    }

    private enum ParserMode {
        case preamble
        case header
        case body
    }

    private func classifyLine(_ str: String, source: SourceRange, mode: ParserMode) -> LogicalLine {
        if str.isEmpty || str.allSatisfy({ $0 == " " || $0 == "\t" }) {
            return .empty(source: source)
        }

        if str.hasPrefix("%abc-") {
            let version = String(str.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            return .versionLine(version: version, source: source)
        }

        if str.hasPrefix("%%") {
            let rest = String(str.dropFirst(2))
            if let spaceIdx = rest.firstIndex(of: " ") {
                let name = String(rest[rest.startIndex..<spaceIdx])
                let payload = String(rest[rest.index(after: spaceIdx)...])
                return .directive(name: name, payload: payload, source: source)
            }
            return .directive(name: rest, payload: "", source: source)
        }

        if str.hasPrefix("%") {
            return .comment(text: String(str.dropFirst()), source: source)
        }

        // Information field: single letter followed by ':'
        if str.count >= 2 {
            let chars = str.unicodeScalars
            let first = Character(chars.first!)
            let second = Character(chars[chars.index(after: chars.startIndex)])
            if first.isLetter && second == ":" {
                let payload = str.count > 2 ? String(str[str.index(str.startIndex, offsetBy: 2)...]) : ""
                return .informationField(code: first, payload: payload, source: source)
            }
        }

        if case .body = mode {
            return .musicLine(text: str, source: source)
        }
        return .freeText(text: str, source: source)
    }
}
