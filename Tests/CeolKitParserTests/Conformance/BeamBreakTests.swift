// Beam breaks: abcm2ps's !beambr1! and !beambr2! (issue #243).
import Testing
import CeolKitModel
import CeolKitParser

private func beamTune(_ body: String) -> String {
    "X:1\nT:Test\nM:2/4\nL:1/16\nK:D\n\(body)|"
}

@Suite("Beam breaks (#243)")
struct BeamBreakTests {

    @Test("!beambr1! and !beambr2! record a beam break on the note they precede")
    func recordedOnNote() throws {
        let result = parse(beamTune("Bc!beambr1!de f!beambr2!g"))
        let notes = try #require(result.score.firstTune?.singleVoiceMeasures.first?.noteEvents)
        let breaks = notes.map(\.beamBreak)
        #expect(breaks == [nil, nil, 1, nil, nil, 2])
        #expect(notes[2].decorations == [.beamBreak(1)])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A beam break on a chord is recorded on the chord")
    func recordedOnChord() throws {
        let result = parse(beamTune("Bc!beambr1![df]e"))
        let chord = try #require(result.score.firstTune?.singleVoiceMeasures.first?.chordEvents.first)
        #expect(chord.beamBreak == 1)
    }

    @Test("A beam break after a space belongs to the next note, not the one before")
    func notRetroactive() throws {
        let result = parse(beamTune("Bc !beambr1!de"))
        let notes = try #require(result.score.firstTune?.singleVoiceMeasures.first?.noteEvents)
        let breaks = notes.map(\.beamBreak)
        #expect(breaks == [nil, nil, 1, nil])
    }

    @Test("A beam break on a rest is dropped with a warning")
    func onRest() throws {
        let result = parse(beamTune("Bc!beambr1!z2"))
        let rest = try #require(result.score.firstTune?.singleVoiceMeasures.first?.restEvents.first)
        #expect(rest.decorations.isEmpty)
        let warnings = result.diagnostics.filter { $0.code == .misplacedBeamBreak }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
    }
}
