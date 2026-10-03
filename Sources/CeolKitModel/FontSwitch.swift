/// The in-string font switches of ABC v2.2 §11.4.2 (issue #204): `$1` … `$4` set the rest
/// of a text string in the face `%%setfont-1` … `%%setfont-4` names, `$0` returns to the
/// string's own font, and `$$` is a dollar sign.
///
/// The switches stay in every ``TextString`` as written — they are how the author asked for
/// the text to be set, not part of the text — and a renderer reads them out with
/// ``runs(in:startingWith:)``.  ``plainText(_:)`` is the text with them taken out, for
/// anything that wants the words rather than their typesetting.
///
/// Only `$0` … `$4` are switches, the four §11.4.2 defines.  A `$` before anything else —
/// `$5`, `$x`, a `$` at the end — is an ordinary dollar sign.
public enum FontSwitch {
    /// The font a run is set in: `0` the string's own, `1` … `4` the `%%setfont-n` face.
    public typealias Font = Int

    /// The highest switch, `$4`.
    public static let maxFont: Font = 4

    /// A stretch of a string set in one font.
    public struct Run: Hashable, Sendable {
        public let font: Font
        public let text: String

        public init(font: Font, text: String) {
            self.font = font
            self.text = text
        }
    }

    /// `text` split at its switches into the runs it is set in, `$$` read as `$`.
    ///
    /// - Parameter font: the font in force where `text` begins — `0` for a string of its
    ///   own; a `w:` line carries a switch on from one syllable to the next.
    /// - Returns: the runs, with no empty ones, and the font in force where `text` ends.
    public static func runs(in text: String, startingWith font: Font = 0)
        -> (runs: [Run], endFont: Font) {
        var runs: [Run] = []
        var current = font
        var pending = ""
        var index = text.startIndex
        func flush() {
            if !pending.isEmpty { runs.append(Run(font: current, text: pending)) }
            pending = ""
        }
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "$", next < text.endIndex {
                let following = text[next]
                if following == "$" {
                    pending.append("$")
                    index = text.index(after: next)
                    continue
                }
                if let digit = following.wholeNumberValue, following.isASCII,
                   (0...maxFont).contains(digit) {
                    flush()
                    current = digit
                    index = text.index(after: next)
                    continue
                }
            }
            pending.append(character)
            index = next
        }
        flush()
        return (runs, current)
    }

    /// `text` as it reads, with its switches taken out and `$$` read as `$`.
    public static func plainText(_ text: String) -> String {
        guard text.contains("$") else { return text }
        return runs(in: text).runs.map(\.text).joined()
    }

    /// The switches `text` makes, `$0` excepted, in the order written.
    public static func fonts(switchedTo text: String) -> [Font] {
        guard text.contains("$") else { return [] }
        var fonts: [Font] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index] == "$", next < text.endIndex {
                let following = text[next]
                if following == "$" {
                    index = text.index(after: next)
                    continue
                }
                if let digit = following.wholeNumberValue, following.isASCII,
                   (1...maxFont).contains(digit) {
                    fonts.append(digit)
                }
            }
            index = next
        }
        return fonts
    }
}
