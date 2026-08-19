// Per-voice K: and L: — issue #66.
//
// ABC §7.3 asks for a field that sets a music property to be repeated in every voice it
// applies to. That instruction is only meaningful if a `K:` or `L:` written in one voice
// leaves the others alone, so these check that it does, and that what each voice opens in
// reaches the model where a renderer can find it.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Per-voice key and unit note length")
struct VoiceKeyAndLengthTests {

    private static let twoVoiceHeader = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nV:1\nV:2\n"

    private func parseTune(_ abc: String) -> Tune? { parse(abc).score.firstTune }

    private func voice(_ tune: Tune?, _ id: String) -> Voice? {
        tune?.voices.first { $0.id == .named(id) }
    }

    // MARK: Key

    @Test("A voice's own K: is recorded on that voice and nowhere else")
    func voiceKeyIsRecordedOnItsOwnVoice() throws {
        let tune = try #require(parseTune(Self.twoVoiceHeader + "V:1\nK:G\nCDEF|\nV:2\nCDEF|\n"))
        let one = try #require(voice(tune, "1"))
        let two = try #require(voice(tune, "2"))

        #expect(one.key?.tonic?.step == .g)
        #expect(tune.effectiveKey(for: one).tonic?.step == .g)
        // Voice 2 stated nothing, so it keeps the tune's C — and says so by holding nil
        // rather than a copy of it.
        #expect(two.key == nil)
        #expect(tune.effectiveKey(for: two).tonic?.step == .c)
        // The tune's own K: is untouched by either.
        #expect(tune.key.tonic?.step == .c)
    }

    @Test("A K: written part way through a voice is a key change, not the key it opens in")
    func midVoiceKeyChangeIsNotTheOpeningKey() throws {
        let tune = try #require(parseTune(Self.twoVoiceHeader + "[V:1] CDEF | [K:G] GAFc |\n[V:2] CDEF|CDEF|\n"))
        let one = try #require(voice(tune, "1"))
        // Nothing to draw at the head of the staff but the tune's key: the change belongs to
        // bar 2, and a signature drawn at bar 1 would be wrong for bar 1.
        #expect(one.key == nil)
        #expect(tune.effectiveKey(for: one).tonic?.step == .c)
        // It still moved the voice's accidentals: F in bar 2 is F# under G major.
        let bars = one.allMeasures
        guard bars.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let barTwo = bars[1].noteEvents
        #expect(barTwo.contains { $0.pitch.step == .f && $0.pitch.alteration == Alteration(numerator: 1, denominator: 1) })
    }

    @Test("Each voice opens in the key it stated for itself")
    func voicesOpenInTheirOwnKeys() throws {
        let tune = try #require(parseTune(Self.twoVoiceHeader + "V:1\nK:G\nCDEF|\nV:2\nK:F\nCDEF|\n"))
        #expect(voice(tune, "1")?.key?.tonic?.step == .g)
        #expect(voice(tune, "2")?.key?.tonic?.step == .f)
    }

    // MARK: Unit note length

    @Test("A voice's own L: is recorded on that voice and nowhere else")
    func voiceUnitNoteLengthIsRecordedOnItsOwnVoice() throws {
        let tune = try #require(parseTune(Self.twoVoiceHeader + "V:1\nL:1/8\nCDEF|\nV:2\nCDEF|\n"))
        let one = try #require(voice(tune, "1"))
        let two = try #require(voice(tune, "2"))

        #expect(one.unitNoteLength == Fraction(numerator: 1, denominator: 8))
        #expect(tune.effectiveUnitNoteLength(for: one) == Fraction(numerator: 1, denominator: 8))
        #expect(two.unitNoteLength == nil)
        #expect(tune.effectiveUnitNoteLength(for: two) == Fraction(numerator: 1, denominator: 4))
        #expect(tune.unitNoteLength == Fraction(numerator: 1, denominator: 4))
    }

    @Test("An inline [L:] at the head of a voice is that voice's, not its neighbour's")
    func inlineUnitNoteLengthDoesNotLeakToTheNextVoice() throws {
        let tune = try #require(parseTune(Self.twoVoiceHeader + "[V:1][L:1/16] CDEF|\n[V:2] CDEF|\n"))
        #expect(voice(tune, "1")?.unitNoteLength == Fraction(numerator: 1, denominator: 16))
        #expect(voice(tune, "2")?.unitNoteLength == nil)
    }

    // MARK: Single voice

    @Test("A single-voice tune with no K:/L: of its own is unchanged")
    func singleVoiceInheritsTheTune() throws {
        let tune = try #require(parseTune("X:1\nT:T\nM:4/4\nL:1/8\nK:D\nabcd efga|\n"))
        let only = try #require(tune.voices.first)
        #expect(only.key == nil)
        #expect(only.unitNoteLength == nil)
        #expect(tune.effectiveKey(for: only).tonic?.step == .d)
        #expect(tune.effectiveUnitNoteLength(for: only) == Fraction(numerator: 1, denominator: 8))
    }
}
