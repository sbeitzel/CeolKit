// "@x,y text" annotations. ABC §4.19.
//
// Issue #304: §4.19 leaves where `@` text goes to the program; the `x,y` offset is
// abcm2ps's convention. abcm2ps reads it with `sscanf(p, "%f,%f%n", …)`, skips one space
// after it if there is one, and takes the rest as the text, so `"@2,3at"` is `at` at (2, 3).
// CeolKit split at the first space instead and kept `2,3at` as the text, at the note.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Absolute annotations (\"@x,y text\")")
struct AbsoluteAnnotationTests {

    private func annotation(_ quoted: String) throws -> (Annotation, [Diagnostic]) {
        let result = parse("X:1\nL:1/4\nK:C\n\"\(quoted)\"C|")
        let measure = try #require(result.score.firstTune?.singleVoiceMeasures.first)
        let note = try #require(measure.noteEvents.first)
        let annotation = try #require(note.annotations.first)
        let diagnostics = result.score.diagnostics.filter { $0.code == .malformedAnnotationOffset }
        return (annotation, diagnostics)
    }

    @Test("The text may follow the offset with no space", arguments: [
        ("@2,3at", 2.0, 3.0, "at"),
        ("@2,3 at", 2.0, 3.0, "at"),
        ("@-1,2 sp", -1.0, 2.0, "sp"),
        ("@-1.5,0.5x", -1.5, 0.5, "x"),
        ("@+.5,3.  two  spaces", 0.5, 3.0, " two  spaces"),
        ("@1, 2text", 1.0, 2.0, "text"),
        ("@1,2e1x", 1.0, 20.0, "x"),
        ("@1,2each", 1.0, 2.0, "each"),
        ("@0,0", 0.0, 0.0, ""),
    ])
    func offsetThenText(quoted: String, x: Double, y: Double, text: String) throws {
        let (annotation, diagnostics) = try annotation(quoted)
        #expect(annotation.position == .absolute(x: x, y: y))
        #expect(annotation.text.value == text)
        #expect(diagnostics.isEmpty)
    }

    @Test("Without an offset the whole text is set at the note, with a warning", arguments: [
        "@this $2was difficult to parse?",
        "@2 at",
        "@2;3 at",
        "@,3 at",
        "@",
    ])
    func noOffset(quoted: String) throws {
        let (annotation, diagnostics) = try annotation(quoted)
        #expect(annotation.position == .absolute(x: 0, y: 0))
        #expect(annotation.text.value == String(quoted.dropFirst()))
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .warning)
    }
}
