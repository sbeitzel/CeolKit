import Testing
@testable import CeolKitSVGRenderer

@Suite("TitleFormatParser")
struct TitleFormatParserTests {

    private typealias Entry = TitleFormatSpec.Entry
    private typealias Box   = TitleFormatSpec.Box
    private typealias Align = TitleFormatSpec.Alignment

    // MARK: - Empty / trivial inputs

    @Test("Empty string produces default (no boxes)")
    func emptyString() {
        let spec = TitleFormatParser.parse("")
        #expect(spec.boxes.isEmpty)
    }

    @Test("Whitespace-only string produces no boxes")
    func whitespaceOnly() {
        let spec = TitleFormatParser.parse("   ")
        #expect(spec.boxes.isEmpty)
    }

    @Test("Trailing comma alone produces no non-empty boxes")
    func trailingCommaOnly() {
        let spec = TitleFormatParser.parse(",")
        #expect(spec.boxes.isEmpty)
    }

    // MARK: - Single letter, various placements

    @Test("Single letter without placement defaults to center")
    func singleLetterNoPlaement() {
        let spec = TitleFormatParser.parse("T")
        #expect(spec.boxes.count == 1)
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .center, concatWithPrevious: false)])
    }

    @Test("Letter with '0' is center")
    func letter0IsCenter() {
        let spec = TitleFormatParser.parse("T0")
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .center, concatWithPrevious: false)])
    }

    @Test("Letter with '1' is right")
    func letter1IsRight() {
        let spec = TitleFormatParser.parse("T1")
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .right, concatWithPrevious: false)])
    }

    @Test("Letter with '-' alone is left")
    func letterDashIsLeft() {
        let spec = TitleFormatParser.parse("T-")
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .left, concatWithPrevious: false)])
    }

    @Test("Letter with '-1' is left")
    func letterMinus1IsLeft() {
        let spec = TitleFormatParser.parse("T-1")
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .left, concatWithPrevious: false)])
    }

    // MARK: - Concatenation

    @Test("'+' between two letters sets concatWithPrevious on second")
    func concatPlus() {
        let spec = TitleFormatParser.parse("X+T")
        #expect(spec.boxes.count == 1)
        let entries = spec.boxes[0].entries
        #expect(entries.count == 2)
        #expect(entries[0] == Entry(fieldCode: "X", alignment: .center, concatWithPrevious: false))
        #expect(entries[1] == Entry(fieldCode: "T", alignment: .center, concatWithPrevious: true))
    }

    // MARK: - Multiple boxes (comma separator)

    @Test("Comma separates two boxes")
    func twoBoxes() {
        let spec = TitleFormatParser.parse("T0, R-1 C1")
        #expect(spec.boxes.count == 2)
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .center, concatWithPrevious: false)])
        #expect(spec.boxes[1].entries == [
            Entry(fieldCode: "R", alignment: .left,  concatWithPrevious: false),
            Entry(fieldCode: "C", alignment: .right, concatWithPrevious: false),
        ])
    }

    @Test("Complex format: R- X+T C1O1")
    func complexFormat() {
        let spec = TitleFormatParser.parse("R- X+T C1O1")
        #expect(spec.boxes.count == 1)
        let entries = spec.boxes[0].entries
        #expect(entries.count == 5)
        #expect(entries[0] == Entry(fieldCode: "R", alignment: .left,   concatWithPrevious: false))
        #expect(entries[1] == Entry(fieldCode: "X", alignment: .center, concatWithPrevious: false))
        #expect(entries[2] == Entry(fieldCode: "T", alignment: .center, concatWithPrevious: true))
        #expect(entries[3] == Entry(fieldCode: "C", alignment: .right,  concatWithPrevious: false))
        #expect(entries[4] == Entry(fieldCode: "O", alignment: .right,  concatWithPrevious: false))
    }

    // MARK: - Whitespace tolerance

    @Test("Spaces between tokens are ignored")
    func spacesIgnored() {
        let spec = TitleFormatParser.parse("  T  0  ")
        #expect(spec.boxes.count == 1)
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .center, concatWithPrevious: false)])
    }

    // MARK: - abc2svg quoted-string skipping

    @Test("Quoted abc2svg strings are skipped")
    func quotedStringSkipped() {
        // "<"$1$X$0 - $T" should produce no entries from inside the quote
        let spec = TitleFormatParser.parse("\"$T\"")
        #expect(spec.boxes.isEmpty)
    }

    @Test("Letter before a quoted string is still parsed")
    func letterBeforeQuote() {
        let spec = TitleFormatParser.parse("T\"ignored\"")
        #expect(spec.boxes.count == 1)
        #expect(spec.boxes[0].entries == [Entry(fieldCode: "T", alignment: .center, concatWithPrevious: false)])
    }

    // MARK: - Trailing empty boxes dropped

    @Test("Trailing comma produces no extra empty box")
    func trailingComma() {
        let spec = TitleFormatParser.parse("T0,")
        #expect(spec.boxes.count == 1)
    }

    @Test("Leading comma produces no leading empty box")
    func leadingComma() {
        let spec = TitleFormatParser.parse(",T0")
        #expect(spec.boxes.count == 1)
    }
}
