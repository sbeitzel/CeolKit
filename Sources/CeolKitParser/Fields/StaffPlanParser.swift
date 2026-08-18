import CeolKitModel

/// Parses the payload of `%%score` / `%%staves` (ABC v2.2 §11.1) into a `StaffPlan`.
///
/// The line classifier splits `%%name payload` on the first space only, with no bracket
/// or quote awareness (`LineClassifier.swift:79-87`), so every delimiter in the payload
/// is this parser's business.
///
/// The two spellings share a grammar and differ only in the sense of `|`: in `%%score` a
/// `|` means the bar lines continue across that boundary, in `%%staves` it means they do
/// not.  The inversion is applied while the tree is built, so `%%staves [S|A|T|B]` and
/// `%%score [S A T B]` yield the same structure.
///
/// On any syntax error the whole directive is dropped rather than stored as a partial
/// tree, matching how the other directives recover.
enum StaffPlanParser {

    /// - Parameters:
    ///   - name: the directive name as written, `"score"` or `"staves"`.
    ///   - payload: everything after the first space of the directive line.
    ///   - source: the range of the whole directive line.
    static func parse(
        name: String,
        payload: String,
        source: SourceRange
    ) -> (StaffPlan?, [Diagnostic]) {
        // The payload begins after "%%", the name, and the single separating space.
        let origin = source.byteOffset + 2 + name.utf8.count + 1
        var parser = Parser(
            payload: payload,
            origin: origin,
            line: source,
            directiveName: name,
            invertJoints: name == "staves"
        )
        do {
            let root = try parser.parsePlan()
            return (StaffPlan(root: root, source: source), [])
        } catch let error as PlanError {
            return (nil, [error.diagnostic])
        } catch {
            return (nil, [])
        }
    }

    // MARK: - Recursive descent

    private struct PlanError: Error {
        let diagnostic: Diagnostic
    }

    private struct Parser {
        /// Each character of the payload with its absolute UTF-8 offset.  Columns are
        /// byte-based here, as they are in `MusicLexer.makeRange`.
        private let items: [(ch: Character, offset: Int)]
        private let endOffset: Int
        private let line: SourceRange
        private let directiveName: String
        private let invertJoints: Bool
        private var index = 0

        init(payload: String, origin: Int, line: SourceRange, directiveName: String, invertJoints: Bool) {
            var items: [(ch: Character, offset: Int)] = []
            var offset = origin
            for ch in payload {
                items.append((ch, offset))
                offset += ch.utf8.count
            }
            self.items = items
            self.endOffset = offset
            self.line = line
            self.directiveName = directiveName
            self.invertJoints = invertJoints
        }

        mutating func parsePlan() throws -> StaffPlanBranch {
            let root = try parseBranch(opener: nil, openIndex: 0)
            skipSpace()
            if let ch = current {
                throw error("'\(ch)' is left over after the end of the staff plan", at: index)
            }
            return root
        }

        /// - Parameters:
        ///   - opener: the delimiter this branch was opened with, or `nil` at the top level.
        ///   - openIndex: where that delimiter was, so an unclosed group points at it.
        private mutating func parseBranch(opener: Character?, openIndex: Int) throws -> StaffPlanBranch {
            let closer = opener.map(Self.closer(for:))
            skipSpace()
            if current == "|" {
                throw error("A '|' cannot open \(subject(opener))", at: index)
            }
            guard let head = try parseNode() else {
                throw error(
                    opener == nil
                        ? "%%\(directiveName) needs at least one voice"
                        : "Empty staff group '\(opener!)\(closer!)'",
                    at: index
                )
            }

            var tail: [StaffPlanBranch.Sibling] = []
            while true {
                skipSpace()
                guard let ch = current else {
                    if let opener {
                        throw error("Unclosed '\(opener)' in the staff plan", at: openIndex)
                    }
                    break
                }
                if ch == closer {
                    index += 1
                    break
                }
                if Self.isCloser(ch) {
                    throw error(
                        opener == nil
                            ? "'\(ch)' closes a staff group that was never opened"
                            : "'\(ch)' does not close the '\(opener!)' it was reached from",
                        at: index
                    )
                }

                var barLine = false
                if ch == "|" {
                    barLine = true
                    index += 1
                    skipSpace()
                }
                guard let node = try parseNode() else {
                    throw error(
                        barLine
                            ? "A '|' must be followed by a voice or a staff group"
                            : "'\(ch)' is not valid in a staff plan",
                        at: index
                    )
                }
                tail.append(StaffPlanBranch.Sibling(joint: joint(barLine: barLine), node: node))
            }

            return StaffPlanBranch(head: head, tail: tail)
        }

        /// Returns `nil` where a node cannot start — end of input, a closing delimiter,
        /// or a `|` — leaving the caller to decide whether that is an error.
        private mutating func parseNode() throws -> StaffPlanNode? {
            skipSpace()
            guard let ch = current else { return nil }
            if ch == "|" || Self.isCloser(ch) { return nil }

            switch ch {
            case "(", "{", "[":
                let openIndex = index
                index += 1
                let branch = try parseBranch(opener: ch, openIndex: openIndex)
                switch ch {
                case "(": return .shared(branch)
                case "{": return .brace(branch)
                default:  return .bracket(branch)
                }
            case "*":
                let start = index
                index += 1
                guard let id = scanVoiceId() else {
                    throw error("'*' marks a floating voice and must be followed by a voice id", at: start)
                }
                return .voice(StaffPlanVoice(
                    id: .named(id),
                    isFloating: true,
                    source: range(from: start, to: index)
                ))
            default:
                let start = index
                guard let id = scanVoiceId() else {
                    throw error("'\(ch)' is not valid in a staff plan", at: index)
                }
                return .voice(StaffPlanVoice(
                    id: .named(id),
                    isFloating: false,
                    source: range(from: start, to: index)
                ))
            }
        }

        // MARK: Scanning

        private var current: Character? {
            index < items.count ? items[index].ch : nil
        }

        private mutating func skipSpace() {
            while let ch = current, ch == " " || ch == "\t" {
                index += 1
            }
        }

        private mutating func scanVoiceId() -> String? {
            let start = index
            while let ch = current, Self.isVoiceIdCharacter(ch) {
                index += 1
            }
            guard index > start else { return nil }
            return String(items[start..<index].map(\.ch))
        }

        private static func isVoiceIdCharacter(_ ch: Character) -> Bool {
            ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "."
        }

        private static func isCloser(_ ch: Character) -> Bool {
            ch == ")" || ch == "}" || ch == "]"
        }

        private static func closer(for opener: Character) -> Character {
            switch opener {
            case "(": return ")"
            case "{": return "}"
            default:  return "]"
            }
        }

        private func subject(_ opener: Character?) -> String {
            opener == nil ? "a staff plan" : "a staff group"
        }

        private func joint(barLine: Bool) -> StaffPlanJoint {
            barLine != invertJoints ? .continuedBarline : .separate
        }

        // MARK: Source ranges

        /// The range of `items[start..<end]`, or a zero-width range at end of input.
        private func range(from start: Int, to end: Int) -> SourceRange {
            let byteOffset = start < items.count ? items[start].offset : endOffset
            let endByte = end < items.count ? items[end].offset : endOffset
            return SourceRange(
                file: line.file,
                byteOffset: byteOffset,
                length: max(0, endByte - byteOffset),
                line: line.line,
                column: line.column + (byteOffset - line.byteOffset)
            )
        }

        private func error(_ message: String, at index: Int) -> PlanError {
            PlanError(diagnostic: Diagnostic(
                severity: .warning,
                code: .invalidStaffPlan,
                message: message,
                source: range(from: index, to: index + 1)
            ))
        }
    }
}
