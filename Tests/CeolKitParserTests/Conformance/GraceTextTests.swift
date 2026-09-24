// Quoted text written before a grace group. ABC §4.18–§4.20.
//
// Issue #176: `"^text"{g}A` put the annotation on the grace note, where nothing draws it.
// §4.20 orders grace notes before chord symbols and annotations, but pipe music writes the
// text first as often as not, and abcm2ps attaches it to the main note.
import Testing
import CeolKitModel
import CeolKitParser

private func graceTune(_ body: String) -> String {
    "X:1\nT:Test\nM:6/8\nL:1/8\nK:D\n\(body)|]"
}

@Suite("Quoted text before a grace group")
struct GraceTextTests {

    private func firstMeasure(_ body: String) throws -> Measure {
        let result = parse(graceTune(body))
        return try #require(result.score.firstTune?.singleVoiceMeasures.first)
    }

    @Test("\"^x\"{g}A puts the annotation on A, not the grace note")
    func annotationBeforeGraceGoesToMainNote() throws {
        let measure = try firstMeasure(#""^x"{g}A>ee e2 d"#)
        let grace = try #require(measure.graceEvents.first)
        let main = try #require(measure.noteEvents.first)
        #expect(grace.notes.allSatisfy { $0.annotations.isEmpty })
        #expect(main.annotations.map(\.text.value) == ["x"])
        #expect(main.annotations.first?.position == .above)
    }

    @Test("\"G\"{g}A puts the chord symbol on A, not the grace note")
    func chordSymbolBeforeGraceGoesToMainNote() throws {
        let measure = try firstMeasure(#""G"{g}A>ee e2 d"#)
        let grace = try #require(measure.graceEvents.first)
        let main = try #require(measure.noteEvents.first)
        #expect(grace.notes.allSatisfy { $0.chordSymbol == nil })
        #expect(main.chordSymbol?.raw == "G")
    }

    @Test("Text passes over a multi-note grace group to the note after it")
    func textPassesOverEveryGraceNote() throws {
        let measure = try firstMeasure(#""^x""D"{gAg}A>ee e2 d"#)
        let grace = try #require(measure.graceEvents.first)
        let main = try #require(measure.noteEvents.first)
        #expect(grace.notes.count == 3)
        #expect(grace.notes.allSatisfy { $0.annotations.isEmpty && $0.chordSymbol == nil })
        #expect(main.annotations.map(\.text.value) == ["x"])
        #expect(main.chordSymbol?.raw == "D")
    }

    @Test("Text written after the grace group still goes to the main note")
    func textAfterGraceIsUnchanged() throws {
        let measure = try firstMeasure(#"{g}"^x"A>ee e2 d"#)
        let main = try #require(measure.noteEvents.first)
        #expect(main.annotations.map(\.text.value) == ["x"])
    }

    @Test("A decoration inside the braces still belongs to the grace note")
    func decorationInsideGraceStaysOnGraceNote() throws {
        let measure = try firstMeasure(#""^x"{!accent!g}A>ee e2 d"#)
        let grace = try #require(measure.graceEvents.first)
        let graceNote = try #require(grace.notes.first)
        let main = try #require(measure.noteEvents.first)
        #expect(graceNote.decorations.contains(.accent))
        #expect(!main.decorations.contains(.accent))
        #expect(main.annotations.map(\.text.value) == ["x"])
    }
}
