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
            // it.  §6.1.1 has those interrupting lines take effect *at the physical line
            // break*, which is the whole reason to write a backslash, so each is spliced
            // into the joined text as its inline equivalent.  A line with no inline form —
            // `w:` above all — is set aside and emitted after the music line it
            // interrupted, so it still lands on the line it belongs to.  Comments are
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
                    if let inline = Self.inlineEquivalent(of: line) {
                        cont.text += inline
                    } else {
                        cont.deferred.append(line)
                    }
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

        return joiningContinuedLyrics(result)
    }

    /// The `[code:payload]` text a line interrupting a `\\` continuation is equivalent to
    /// (§6.1.1), or `nil` when it has no inline form and must be deferred to the end of the
    /// joined line instead.
    private static func inlineEquivalent(of line: LogicalLine) -> String? {
        switch line {
        case .informationField(let code, let payload, _):
            guard inlineLegalFieldCodes.contains(code) else { return nil }
            return bracketed(code: code, payload: payload)
        case .directive(let name, let payload, _):
            // §4.4: the stylesheet directive `%%name payload` is the field `I:name payload`.
            return bracketed(code: "I", payload: payload.isEmpty ? name : "\(name) \(payload)")
        default:
            return nil
        }
    }

    /// §4.19: the field codes that may be written inline in a line of music code.  `w:` is
    /// pointedly not among them.
    private static let inlineLegalFieldCodes: Set<Character> = [
        "I", "K", "L", "M", "m", "N", "P", "Q", "R", "r", "s", "U", "V", "W",
    ]

    private static func bracketed(code: Character, payload: String) -> String? {
        // An inline field ends at the first `]`, so a payload carrying one has no inline
        // form at all and the line keeps its deferral rather than being truncated.
        guard !payload.contains("]") else { return nil }
        return "[\(code):\(payload)]"
    }

    /// Joins a `w:` line that ends in `\\` to the one after it (§2.2).
    ///
    /// A continued music line takes its lyrics with it: the source writes one `w:` for the
    /// half of the line before the break and another for the half after, and the two are one
    /// verse of the one music line the classifier has just joined.  Left apart they would
    /// each be aligned from the start of that line, and the second would print as a spurious
    /// second verse under the first.
    ///
    /// The join is done here rather than in ``LyricParser`` because the continuation is a
    /// property of the *line*, exactly as it is for the music above it, and by the time the
    /// payload is tokenised the line it came from is gone.
    private func joiningContinuedLyrics(_ lines: [LogicalLine]) -> [LogicalLine] {
        // Nothing to do for the overwhelming majority of sources, which continue no lyric.
        guard lines.contains(where: { Self.continuedLyricPayload(of: $0) != nil }) else {
            return lines
        }
        var result: [LogicalLine] = []
        result.reserveCapacity(lines.count)
        // The head of a continued run: its payload so far, and where it began.
        var pending: (payload: String, source: SourceRange)?

        for line in lines {
            if var open = pending, case .informationField(let code, let payload, _) = line,
               code == "w" {
                // The line the run was waiting for.  It may itself be continued, in which
                // case the run stays open and gathers the one after that as well.
                open.payload += " " + payload
                if let more = Self.dropContinuation(open.payload) {
                    pending = (payload: more, source: open.source)
                } else {
                    pending = nil
                    result.append(.informationField(code: "w", payload: open.payload,
                                                    source: open.source))
                }
                continue
            }
            if let open = pending {
                // Nothing joined it: the source ended, or wrote something else next.  The
                // half-line still stands on its own, without its continuation mark.
                result.append(.informationField(code: "w", payload: open.payload,
                                                source: open.source))
                pending = nil
            }
            if let payload = Self.continuedLyricPayload(of: line) {
                pending = (payload: payload, source: line.source)
                continue
            }
            result.append(line)
        }
        if let open = pending {
            result.append(.informationField(code: "w", payload: open.payload, source: open.source))
        }
        return result
    }

    /// The payload of a `w:` line that ends in `\\`, without the backslash; `nil` for
    /// anything else.
    private static func continuedLyricPayload(of line: LogicalLine) -> String? {
        guard case .informationField(let code, let payload, _) = line, code == "w" else {
            return nil
        }
        return dropContinuation(payload)
    }

    private static func dropContinuation(_ payload: String) -> String? {
        let trimmed = payload.hasSuffix(" ") ? String(payload.reversed().drop { $0 == " " }.reversed())
                                             : payload
        guard trimmed.hasSuffix("\\") else { return nil }
        return String(trimmed.dropLast())
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
