/// Structured representation of a parsed %%titleformat string.
///
/// A format string describes one or more "boxes" (rows) separated by commas.
/// Each box contains entries that map ABC header field codes to alignment zones
/// (left / center / right) within the row.
public struct TitleFormatSpec: Sendable, Equatable {
    public let boxes: [Box]

    public static let `default` = TitleFormatSpec(boxes: [])

    public init(boxes: [Box]) {
        self.boxes = boxes
    }

    /// One row in the rendered title block, delimited from others by ','.
    public struct Box: Sendable, Equatable {
        public let entries: [Entry]

        public init(entries: [Entry]) {
            self.entries = entries
        }
    }

    /// One field slot within a box.
    public struct Entry: Sendable, Equatable {
        /// The ABC header field letter (e.g. 'T', 'R', 'C', 'X').
        public let fieldCode: Character
        public let alignment: Alignment
        /// True when '+' precedes this entry, meaning its value is concatenated inline
        /// with the previous entry's value rather than stacked as a separate item.
        public let concatWithPrevious: Bool

        public init(fieldCode: Character, alignment: Alignment, concatWithPrevious: Bool) {
            self.fieldCode = fieldCode
            self.alignment = alignment
            self.concatWithPrevious = concatWithPrevious
        }
    }

    public enum Alignment: Sendable, Equatable {
        case left, center, right
    }
}
