import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #229: spans for an editor's syntax coloring.
@Suite("Highlight spans")
struct HighlightingTests {

    /// Each span as its kind and the text it covers, read back out of the LF-normalized
    /// source the ranges count into.
    private func spans(_ abc: String) -> [(HighlightKind, String)] {
        let bytes = Array(abc.replacing(/\r\n/, with: "\n").utf8)
        return CeolKitParser.highlightSpans(in: abc).map { span in
            let slice = bytes[span.range.byteOffset..<(span.range.byteOffset + span.range.length)]
            return (span.kind, String(decoding: slice, as: UTF8.self))
        }
    }

    private func kinds(_ abc: String, matching text: String) -> [HighlightKind] {
        spans(abc).filter { $0.1 == text }.map(\.0)
    }

    private let header = "X:1\nT:t\nK:C\n"

    @Test("A field is its key and its value")
    func field() {
        let found = spans("X:1\nT:The Tune\n")
        #expect(found.map(\.0) == [.fieldKey, .fieldValue, .fieldKey, .fieldValue])
        #expect(found.map(\.1) == ["X:", "1", "T:", "The Tune"])
    }

    @Test("A field's trailing comment is a comment, an escaped percent is not")
    func fieldComment() {
        let found = spans("T:Fifty \\% off % note\n")
        #expect(found.map(\.1) == ["T:", "Fifty \\% off ", "% note"])
        #expect(found.last?.0 == .comment)
    }

    @Test("Comment, directive and version lines")
    func wholeLines() {
        let found = spans("%abc-2.1\n%%scale 0.8\n% hello\n")
        #expect(found.map(\.0) == [.versionLine, .directive, .comment])
    }

    @Test("Text outside a tune is free text")
    func freeText() {
        #expect(kinds("Some notes about the book\n", matching: "Some notes about the book") == [.freeText])
    }

    @Test("A note's accidental, pitch with octave marks, and length")
    func note() {
        let found = spans(header + "^c'3/2\n").suffix(3)
        #expect(found.map(\.0) == [.accidental, .note, .duration])
        #expect(found.map(\.1) == ["^", "c'", "3/2"])
    }

    @Test("Bar lines and endings")
    func bars() {
        let found = spans(header + "|:A:|1B:|2c|]\n").filter { $0.0 == .barLine || $0.0 == .ending }
        #expect(found.map(\.1) == ["|:", ":|", "1", ":|", "2", "|]"])
    }

    @Test("Rests")
    func rests() {
        #expect(kinds(header + "z2 x Z\n", matching: "z") == [.rest])
        #expect(kinds(header + "z2 x Z\n", matching: "Z") == [.rest])
    }

    @Test("Chord symbols and annotations")
    func quoted() {
        let abc = header + "\"G7\"G \"^Fine\"c\n"
        #expect(kinds(abc, matching: "\"G7\"") == [.chordSymbol])
        #expect(kinds(abc, matching: "\"^Fine\"") == [.annotation])
    }

    @Test("A long decoration is one span, a short one its character")
    func decorations() {
        let abc = header + "!trill!c ~d\n"
        #expect(kinds(abc, matching: "!trill!") == [.decoration])
        #expect(kinds(abc, matching: "~") == [.decoration])
    }

    @Test("Grace-note braces, slurs, ties and tuplets")
    func structure() {
        let abc = header + "{/g}A (3B-B(c)\n"
        #expect(kinds(abc, matching: "{/") == [.graceNote])
        #expect(kinds(abc, matching: "}") == [.graceNote])
        #expect(kinds(abc, matching: "(3") == [.slurTieTuplet])
        #expect(kinds(abc, matching: "-") == [.slurTieTuplet])
    }

    @Test("An inline field")
    func inlineField() {
        #expect(kinds(header + "A[K:G]B\n", matching: "[K:G]") == [.inlineField])
    }

    @Test("A music line's trailing comment")
    func musicComment() {
        let found = spans(header + "AB \"%ok\"c % the end\n")
        #expect(found.last?.0 == .comment)
        #expect(found.last?.1 == "% the end")
        #expect(kinds(header + "AB \"%ok\"c % the end\n", matching: "\"%ok\"") == [.chordSymbol])
    }

    @Test("Each continued line keeps its own ranges")
    func continuation() {
        let found = spans(header + "AB\\\ncd|\n")
        #expect(found.suffix(3).map(\.1) == ["AB", "cd", "|"])
    }

    @Test("CRLF line endings")
    func crlf() {
        let found = spans("X:1\r\nT:t\r\nK:C\r\nAB|\r\n")
        #expect(found.suffix(2).map(\.1) == ["AB", "|"])
    }

    @Test("Offsets count UTF-8 bytes past non-ASCII text")
    func nonASCII() {
        let found = spans("X:1\nT:Ceòl 🎻\nK:C\nAB|\n")
        #expect(found.contains { $0 == (.fieldValue, "Ceòl 🎻") })
        #expect(found.suffix(2).map(\.1) == ["AB", "|"])
    }
}
