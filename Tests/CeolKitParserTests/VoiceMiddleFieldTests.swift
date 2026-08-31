import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #80: `V: … middle=` names the pitch on the middle staff line.
///
/// The parser used to drop it into the unknown-key branch, so `VoiceProperties.middleNote`
/// was modelled and never set.  It is read now — as the split a floating voice is assigned
/// by — so the value has to survive the field, octave and all.
@Suite("V: middle=")
struct VoiceMiddleFieldTests {

    private func middle(_ header: String) -> Pitch? {
        properties(header).middleNote
    }

    private func properties(_ header: String) -> VoiceProperties {
        let tune = CeolKitParser().parse("""
        X:1
        L:1/4
        \(header)
        K:C
        V:1
        CDEF|
        """, options: .default).score.tunes[0]
        return tune.voices[0].properties
    }

    private func diagnostics(_ header: String) -> [Diagnostic] {
        CeolKitParser().parse("""
        X:1
        L:1/4
        \(header)
        K:C
        V:1
        CDEF|
        """, options: .default).score.diagnostics
    }

    private func pitch(_ step: DiatonicStep, _ octave: Int,
                       _ alteration: Alteration = .natural) -> Pitch {
        Pitch(step: step, alteration: alteration, octave: octave)
    }

    @Test("A voice that says nothing has no middle note")
    func absent() {
        #expect(middle("V:1 clef=treble") == nil)
    }

    @Test("An upper-case letter is the octave from middle C up")
    func upperCaseIsOctaveFour() {
        #expect(middle("V:1 middle=B") == pitch(.b, 4))
        #expect(middle("V:1 middle=C") == pitch(.c, 4))
    }

    @Test("A lower-case letter is the octave above that")
    func lowerCaseIsOctaveFive() {
        #expect(middle("V:1 middle=d") == pitch(.d, 5))
    }

    @Test("Octave marks shift by an octave each, in either direction")
    func octaveMarks() {
        #expect(middle("V:1 middle=C,") == pitch(.c, 3))
        #expect(middle("V:1 middle=C,,") == pitch(.c, 2))
        #expect(middle("V:1 middle=c'") == pitch(.c, 6))
    }

    @Test("An accidental is kept, because the value is a pitch")
    func accidentals() {
        #expect(middle("V:1 middle=^F") == pitch(.f, 4, .sharp))
        #expect(middle("V:1 middle=_B,") == pitch(.b, 3, .flat))
        #expect(middle("V:1 middle==C") == pitch(.c, 4))
    }

    @Test("`m=` is the same key spelled short")
    func abbreviation() {
        #expect(middle("V:1 m=d") == pitch(.d, 5))
    }

    @Test("It sits alongside the other keys without disturbing them")
    func alongsideOtherKeys() {
        let props = properties("V:1 clef=bass middle=D name=\"Bass\" stem=down")
        #expect(props.middleNote == pitch(.d, 4))
        #expect(props.clef.clef == .bass)
        #expect(props.name == "Bass")
        #expect(props.stemDirection == .down)
    }

    @Test("It is no longer reported as an unknown key")
    func noLongerUnknown() {
        #expect(!diagnostics("V:1 middle=B").contains { $0.code == .unknownKey })
    }

    @Test("A value that is not a note is a warning, and the rest of the field stands")
    func malformedValueWarns() {
        let props = properties("V:1 middle=xyzzy clef=bass")
        #expect(props.middleNote == nil)
        #expect(props.clef.clef == .bass)

        let warnings = diagnostics("V:1 middle=xyzzy").filter {
            $0.code == .malformedFieldPayload
        }
        #expect(warnings.count == 1)
        #expect(warnings.first?.severity == .warning)
    }
}
