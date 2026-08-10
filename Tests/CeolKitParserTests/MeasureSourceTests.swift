import Testing
import CeolKitModel
import CeolKitParser

/// Regression tests for #41: `Measure.source` used to be a fabricated
/// `line 1, column 1, offset 0, length 0` for every measure that did not begin
/// the stave, because the semantic pass dropped the whitespace element's real
/// range and the measure adopted the resulting zeroed spacer.
@Suite("Measure source ranges")
struct MeasureSourceTests {

    /// Byte offset of the first occurrence of `needle`, for expressing expected
    /// ranges as "the range of this text" rather than as magic numbers.
    private func offset(of needle: String, in source: String) -> Int {
        guard let range = source.range(of: needle) else {
            Issue.record("fixture does not contain \(needle)")
            return -1
        }
        return source.utf8.distance(from: source.utf8.startIndex, to: range.lowerBound.samePosition(in: source.utf8)!)
    }

    private static let threeStaves = """
    X:1
    T:t
    M:C
    L:1/8
    K:C
    CDEF GABc | cBAG FEDC |
    |: CDEF GABc | cBAG FEDC :|
    CDEF GABc | cBAG FEDC |
    """

    @Test("Every measure reports the source line its music is on")
    func measureLinesFollowTheSource() {
        let measures = parse(Self.threeStaves).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 6)
        #expect(measures.map(\.source.line) == [6, 6, 7, 7, 8, 8])
    }

    @Test("No measure falls back to the synthetic default range")
    func noMeasureUsesTheFabricatedDefault() {
        let measures = parse(Self.threeStaves).score.firstTune?.singleVoiceMeasures ?? []
        #expect(!measures.isEmpty)
        for measure in measures {
            #expect(measure.source.byteOffset > 0)
            #expect(measure.source.length > 1)
        }
        // Distinct positions: no two measures claim the same spot in the file.
        #expect(Set(measures.map(\.source.byteOffset)).count == measures.count)
    }

    @Test("A measure spans from its first note through its closing barline")
    func measureSpansItsOwnText() {
        let src = Self.threeStaves
        let measures = parse(src).score.firstTune?.singleVoiceMeasures ?? []

        // Stave 0, measure 0: "CDEF GABc |" — starts at the first note, ends
        // after the barline that closes it.
        let first = measures[0].source
        #expect(first.byteOffset == offset(of: "CDEF GABc |", in: src))
        #expect(first.column == 1)
        #expect(src.utf8Slice(at: first) == "CDEF GABc |")

        // Stave 1 opens with "|:" — the measure still starts at its first note,
        // not at the barline, and not at the leading spacer after it.
        let repeated = measures[2].source
        #expect(repeated.line == 7)
        #expect(src.utf8Slice(at: repeated) == "CDEF GABc |")

        // Last measure of the repeated stave closes on ":|".
        #expect(src.utf8Slice(at: measures[3].source) == "cBAG FEDC :|")
    }

    @Test("A measure with no closing barline still spans its events")
    func finalMeasureWithoutBarline() {
        let src = """
        X:1
        T:t
        L:1/8
        K:C
        CDEF GABc | cBAG FEDC
        """
        let measures = parse(src).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 2)
        #expect(measures.map(\.source.line) == [5, 5])
        #expect(src.utf8Slice(at: measures[1].source) == "cBAG FEDC")
    }

    @Test("A measure continued onto the next line spans the break")
    func measureSpanningALineBreak() {
        let src = """
        X:1
        T:t
        M:C
        L:1/8
        K:C
        CDEF GABc | cBAG
        FEDC | CDEF GABc |
        """
        let measures = parse(src).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 3)
        // The second measure starts on line 6 and closes on line 7.
        #expect(measures[1].source.line == 6)
        #expect(src.utf8Slice(at: measures[1].source) == "cBAG\nFEDC |")
        #expect(measures[2].source.line == 7)
    }

    @Test("Spacers carry the range of the whitespace they came from")
    func spacersArePositioned() {
        let src = Self.threeStaves
        let measures = parse(src).score.firstTune?.singleVoiceMeasures ?? []
        let spacers: [Spacer] = measures.flatMap { measure in
            measure.events.compactMap { if case .spacer(let s) = $0 { s } else { nil } }
        }
        #expect(!spacers.isEmpty)
        for spacer in spacers {
            #expect(spacer.source.byteOffset > 0)
            #expect(src.utf8Slice(at: spacer.source) == " ")
        }
    }

    @Test("Measures stay positioned when the stave opens with a barline")
    func staveOpeningWithBarline() {
        let src = """
        X:1
        T:t
        L:1/8
        K:C
        [|: CDEF GABc | cBAG FEDC :|]
        [|: GABc CDEF | FEDC cBAG :|]
        """
        let measures = parse(src).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 4)
        #expect(measures.map(\.source.line) == [5, 5, 6, 6])
        #expect(src.utf8Slice(at: measures[0].source) == "CDEF GABc |")
        #expect(src.utf8Slice(at: measures[3].source) == "FEDC cBAG :|]")
    }
}

private extension String {
    /// The text a `SourceRange` covers, by UTF-8 offset and length.
    func utf8Slice(at range: SourceRange) -> String? {
        let bytes = Array(utf8)
        guard range.byteOffset >= 0,
              range.length >= 0,
              range.byteOffset + range.length <= bytes.count else { return nil }
        return String(decoding: bytes[range.byteOffset..<(range.byteOffset + range.length)], as: UTF8.self)
    }
}
