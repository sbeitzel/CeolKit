// File-header information fields (ABC v2.2 §2.2.2; issue #256).
//
// The fields the §3 table allows in the file header set the default for every tune.  A tune
// overrides them for itself alone, and the next tune starts again from the file header.  A
// repeatable text field follows abcm2ps (8.14, `parse.c`): a tune's first `C:` replaces the
// file header's, and its later ones add to it.  A field the file header may not hold, or one
// written between tunes, is ignored with a warning.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("File-header information fields (#256)")
struct FileHeaderTests {

    private let sixteenth = Fraction(numerator: 1, denominator: 16)
    private let eighth = Fraction(numerator: 1, denominator: 8)
    private let quarter = Fraction(numerator: 1, denominator: 4)

    private func isFraction(_ meter: Meter?, _ num: Int, _ den: Int) -> Bool {
        guard case .fraction(let n, let d) = meter else { return false }
        return n == num && d == den
    }

    private func misplaced(_ result: ParseResult) -> [Diagnostic] {
        result.diagnostics.filter { $0.code == .misplacedField }
    }

    @Test("File-header L:, M:, C: and m: reach the tune")
    func issueExample() {
        let abc = """
            L:1/16
            M:3/4
            C:Someone
            m:~G2 = {A}G{F}G

            X:1
            T:Test
            K:C
            CDEF ~G2|
            """
        let result = parse(abc)
        let tune = result.score.firstTune
        #expect(tune?.unitNoteLength == sixteenth)
        #expect(isFraction(tune?.meter, 3, 4))
        #expect(tune?.metadata.composer.map(\.value) == ["Someone"])
        #expect(tune?.macros.map(\.pattern) == ["~G2"])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A tune's own field overrides the file header for that tune only")
    func overrideEndsWithTune() {
        let abc = """
            L:1/16
            M:3/4

            X:1
            L:1/4
            M:2/4
            K:C
            CD|

            X:2
            K:C
            CDEF|
            """
        let tunes = parse(abc).score.tunes
        #expect(tunes.count == 2)
        #expect(tunes.first?.unitNoteLength == quarter)
        #expect(isFraction(tunes.first?.meter, 2, 4))
        #expect(tunes.last?.unitNoteLength == sixteenth)
        #expect(isFraction(tunes.last?.meter, 3, 4))
    }

    @Test("A tune's first C: replaces the file header's; its later ones add to it")
    func repeatableFieldReplacesThenAdds() {
        let abc = """
            C:Header One
            C:Header Two
            N:Header note

            X:1
            C:Tune One
            C:Tune Two
            K:C
            CDEF|

            X:2
            K:C
            CDEF|
            """
        let tunes = parse(abc).score.tunes
        #expect(tunes.first?.metadata.composer.map(\.value) == ["Tune One", "Tune Two"])
        #expect(tunes.first?.metadata.notes.map(\.value) == ["Header note"])
        #expect(tunes.last?.metadata.composer.map(\.value) == ["Header One", "Header Two"])
    }

    @Test("A tune's m: adds to the file header's macros")
    func macrosAdd() {
        let abc = """
            m:~G2 = {A}G{F}G

            X:1
            m:~A2 = {B}A{G}A
            K:C
            CDEF|
            """
        #expect(parse(abc).score.firstTune?.macros.map(\.pattern) == ["~G2", "~A2"])
    }

    @Test("A file-header M: sets the default unit note length when no L: is given")
    func headerMeterSetsDefaultLength() {
        let abc = "M:2/4\n\nX:1\nK:C\nCDEF|\n"
        #expect(parse(abc).score.firstTune?.unitNoteLength == sixteenth)
    }

    @Test("A file-header L: stands against a tune's own M:")
    func headerLengthBeatsTuneMeterDefault() {
        let abc = "L:1/8\n\nX:1\nM:2/4\nK:C\nCDEF|\n"
        #expect(parse(abc).score.firstTune?.unitNoteLength == eighth)
    }

    @Test("A field the file header may not hold is ignored with a warning")
    func disallowedFieldWarns() {
        let abc = "T:Header Title\nQ:1/4=120\n\nX:1\nT:Tune\nK:C\nCDEF|\n"
        let result = parse(abc)
        #expect(result.score.firstTune?.titles.map(\.value) == ["Tune"])
        #expect(result.score.firstTune?.tempo == nil)
        #expect(misplaced(result).map(\.source.line) == [1, 2])
    }

    @Test("A field between tunes is ignored with a warning")
    func gapFieldWarns() {
        let abc = """
            X:1
            K:C
            CDEF|

            L:1/16
            C:Someone

            X:2
            K:C
            CDEF|
            """
        let result = parse(abc)
        let second = result.score.tunes.last
        #expect(second?.unitNoteLength == eighth)
        #expect(second?.metadata.composer.isEmpty == true)
        #expect(misplaced(result).map(\.source.line) == [5, 6])
    }

    @Test("A tune with no X: takes the block above it as its header")
    func implicitTuneTakesItsOwnBlock() {
        let result = parse("L:1/16\nT:Implicit\nK:C\nCDEF|\n")
        let tune = result.score.firstTune
        #expect(tune?.unitNoteLength == sixteenth)
        #expect(tune?.titles.map(\.value) == ["Implicit"])
        #expect(misplaced(result).isEmpty)
    }

    @Test("A tune with no X: leaves the file header above it to every tune")
    func implicitTuneLeavesFileHeader() {
        let abc = """
            L:1/16

            T:Implicit
            K:C
            CDEF|

            X:2
            K:C
            CDEF|
            """
        let result = parse(abc)
        let tunes = result.score.tunes
        #expect(tunes.count == 2)
        #expect(tunes.first?.titles.map(\.value) == ["Implicit"])
        #expect(tunes.first?.unitNoteLength == sixteenth)
        #expect(tunes.last?.unitNoteLength == sixteenth)
        #expect(misplaced(result).isEmpty)
    }
}
