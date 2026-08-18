// Voice-scoping tests for the semantic pass. Issue #87.
//
// State that belongs to one voice must not reach another. Every one of these needs a *mid-bar*
// voice switch to bite: a voice line that ends on a bar line flushes or resets the state on the
// way past, which is why the single-voice suites never caught any of them.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Voice scoping")
struct VoiceScopeTests {

    private static let twoVoiceHeader = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\nV:1\nV:2\n"

    private func measures(_ result: ParseResult, _ id: String) -> [Measure] {
        result.score.firstTune?.voices.first { $0.id == .named(id) }?.allMeasures ?? []
    }

    // MARK: Slurs

    @Test("A slur opened in voice 1 does not close on voice 2's note")
    func slurDoesNotLeakAcrossVoices() {
        // The `(` is left unconsumed when the voice switches: voice 1 has no note after it.
        let result = parse(Self.twoVoiceHeader + "[V:1] C ( [V:2] D E|\n")
        let one = measures(result, "1").first?.noteEvents ?? []
        let two = measures(result, "2").first?.noteEvents ?? []
        guard !one.isEmpty, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }

        // Voice 2 never opened a slur, so voice 1's dangling `(` must not land on its notes.
        #expect(two.allSatisfy { $0.slurs.opens == 0 })
    }

    // MARK: Grace groups

    @Test("An unterminated grace group in voice 1 does not swallow voice 2's notes")
    func graceGroupDoesNotLeakAcrossVoices() {
        let result = parse(Self.twoVoiceHeader + "[V:1] {ag} c {ag [V:2] d e|\n")
        let two = measures(result, "2").first?.noteEvents ?? []
        guard two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }

        // Voice 2's notes are its own, not buffered into voice 1's open grace group.
        #expect(two.count == 2)
        // And voice 2 has no grace group of its own — the `{` was written in voice 1.
        let graces = measures(result, "2").first?.graceEvents ?? []
        #expect(graces.isEmpty)
    }

    // MARK: Tuplets

    @Test("A tuplet started in voice 1 does not collect voice 2's events")
    func tupletDoesNotLeakAcrossVoices() {
        // No space before the switch: a spacer event would otherwise complete the tuplet early,
        // in voice 1, and the leak would never get a chance to cross.
        let result = parse(Self.twoVoiceHeader + "[V:1] (3ab[V:2] c d e|\n")
        let twoMeasure = measures(result, "2").first

        // Voice 2's notes are plain notes of its own, not the tail of voice 1's open tuplet,
        // and no tuplet voice 1 started may be flushed into voice 2.
        let notes = twoMeasure?.noteEvents ?? []
        let tuplets = twoMeasure?.tupletEvents ?? []
        #expect(notes.count == 3)
        #expect(tuplets.isEmpty)
    }

    // MARK: Pending attachments

    @Test("A pending decoration in voice 1 does not attach to voice 2's note")
    func pendingDecorationDoesNotLeakAcrossVoices() {
        let result = parse(Self.twoVoiceHeader + "[V:1] !trill! [V:2] c d|\n")
        let two = measures(result, "2").first?.noteEvents ?? []
        guard let first = two.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(first.decorations.isEmpty)
    }

    @Test("A pending chord symbol in voice 1 does not attach to voice 2's note")
    func pendingChordSymbolDoesNotLeakAcrossVoices() {
        let result = parse(Self.twoVoiceHeader + "[V:1] \"Am\" [V:2] c d|\n")
        let two = measures(result, "2").first?.noteEvents ?? []
        guard let first = two.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(first.chordSymbol == nil)
    }

    @Test("A pending ending number in voice 1 does not tag voice 2's measure")
    func pendingEndingNumberDoesNotLeakAcrossVoices() {
        let result = parse(Self.twoVoiceHeader + "[V:1] C D |[1 E F [V:2] G A|\n")
        guard let twoFirst = measures(result, "2").first else {
            Issue.record("Parser prerequisite not met"); return
        }
        #expect(twoFirst.endingNumber == nil)
    }

    // MARK: Post-note decoration lookbehind
    //
    // `lastElementWasSpace` moved into VoiceState for consistency, not to fix a leak: it cannot
    // cross a voice switch, because every element resets it before the next one is read and a
    // `[V:…]` switch is itself an element.  This pins that, so the move stays behaviour-neutral.

    @Test("A post-note decoration still attaches across a voice switch boundary")
    func postNoteDecorationUnaffectedByVoiceSwitch() {
        let result = parse(Self.twoVoiceHeader + "[V:1] C [V:2] !trill! D|\n")
        let two = measures(result, "2").first?.noteEvents ?? []
        let one = measures(result, "1").first?.noteEvents ?? []
        guard let firstTwo = two.first, let firstOne = one.first else {
            Issue.record("Parser prerequisite not met"); return
        }
        // The trill is pending when voice 2's D arrives, so it attaches there; voice 1 is clean.
        #expect(firstTwo.decorations.count == 1)
        #expect(firstOne.decorations.isEmpty)
    }

    // MARK: Meter — tune-wide, reported per voice

    @Test("An inline [M:] tags every voice's next measure, not just the first to reach a bar")
    func meterChangeReachesEveryVoice() {
        let result = parse(
            Self.twoVoiceHeader + "[V:1] C D [M:3/4] E F | G A B |\n[V:2] C D E F | G A B |\n"
        )
        let one = measures(result, "1")
        let two = measures(result, "2")
        guard one.count >= 2, two.count >= 2 else { Issue.record("Parser prerequisite not met"); return }

        // The measure containing the change is not tagged; the one after it is — in both voices.
        #expect(one[0].meter == nil)
        #expect(one[1].meter != nil)
        #expect(two[0].meter == nil)
        #expect(two[1].meter != nil)
    }

    @Test("A meter change is reported once per voice, not on every following measure")
    func meterChangeIsReportedOnlyOnce() {
        let result = parse(
            Self.twoVoiceHeader + "[V:1] C D [M:3/4] E F | G A B | c d e |\n[V:2] C D E F | G A B | c d e |\n"
        )
        for id in ["1", "2"] {
            let ms = measures(result, id)
            guard ms.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
            #expect(ms[1].meter != nil, "voice \(id) should report the change once")
            #expect(ms[2].meter == nil, "voice \(id) should not report it again")
        }
    }
}
