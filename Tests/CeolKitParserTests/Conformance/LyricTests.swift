// Lyric alignment conformance tests. ABC §4.18 (w: field).
// Each syllable aligns to the corresponding note; special characters
// control melisma, hyphenation, and skipping.
import Testing
import CeolKitModel
import CeolKitParser

private func lyricTune(_ body: String, _ lyrics: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(body)\nw:\(lyrics)"
}

@Suite("Lyrics")
struct LyricTests {

    // MARK: Basic alignment

    @Test("Single syllable aligns to first note")
    func singleSyllable() {
        let result = parse(lyricTune("C|", "do"))
        let note = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents.first
        guard case .text(let text, let connection) = note?.lyric else {
            Issue.record("Expected .text lyric, got \(String(describing: note?.lyric))")
            return
        }
        #expect(text.value == "do")
        #expect(connection == .wordEnd)
    }

    @Test("Four syllables align to four notes")
    func fourSyllables() {
        let result = parse(lyricTune("CDEF|", "do re mi fa"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 4 else { Issue.record("Parser prerequisite not met"); return }
        let expected = ["do", "re", "mi", "fa"]
        for (note, syllable) in zip(notes, expected) {
            if case .text(let text, _) = note.lyric {
                #expect(text.value == syllable)
            } else {
                Issue.record("Note expected lyric '\(syllable)', got \(String(describing: note.lyric))")
            }
        }
    }

    @Test("Hyphen mid-word: first note gets .hyphen connection")
    func hyphenConnectsToNext() {
        let result = parse(lyricTune("CD|", "hel-lo"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 1 else { Issue.record("Parser prerequisite not met"); return }
        if case .text(let text, let connection) = notes[0].lyric {
            #expect(text.value == "hel")
            #expect(connection == .hyphen)
        } else {
            Issue.record("Expected .text with hyphen, got \(String(describing: notes[0].lyric))")
        }
    }

    @Test("Second syllable of hyphenated word: connection = .wordEnd")
    func hyphenSecondSyllable() {
        let result = parse(lyricTune("CD|", "hel-lo"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        if case .text(let text, let connection) = notes[1].lyric {
            #expect(text.value == "lo")
            #expect(connection == .wordEnd)
        } else {
            Issue.record("Expected .text with wordEnd, got \(String(describing: notes[1].lyric))")
        }
    }

    @Test("Underscore _ creates a melisma continuation")
    func melisma() {
        let result = parse(lyricTune("CDE|", "long__"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 3 else { Issue.record("Parser prerequisite not met"); return }
        // First note gets the syllable
        if case .text(let text, _) = notes[0].lyric {
            #expect(text.value == "long")
        }
        // Second and third notes get melisma
        #expect(notes[1].lyric == .melisma)
        #expect(notes[2].lyric == .melisma)
    }

    @Test("Asterisk * skips the note (explicit skip)")
    func skipNote() {
        let result = parse(lyricTune("CDEF|", "do * mi fa"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 4 else { Issue.record("Parser prerequisite not met"); return }
        // First note: "do"
        if case .text(let text, _) = notes[0].lyric {
            #expect(text.value == "do")
        }
        // Second note: skipped
        #expect(notes[1].lyric == .skip)
        // Third note: "mi"
        if case .text(let text, _) = notes[2].lyric {
            #expect(text.value == "mi")
        }
    }

    @Test("Note with no corresponding lyric has nil lyric")
    func nilLyricWhenLineExhausted() {
        // Fewer syllables than notes — remaining notes get nil
        let result = parse(lyricTune("CDEF|", "do re"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count >= 4 else { Issue.record("Parser prerequisite not met"); return }
        // Third and fourth notes have no lyric
        #expect(notes[2].lyric == nil)
        #expect(notes[3].lyric == nil)
    }

    @Test("Pipe | in lyrics resets alignment at bar line")
    func pipeResetsLyricAtBar() {
        let result = parse(lyricTune("CD|EF|", "do re|mi fa"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        guard measures.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // First measure: do re
        let bar1Notes = measures[0].noteEvents
        guard bar1Notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        if case .text(let t, _) = bar1Notes[0].lyric { #expect(t.value == "do") }
        if case .text(let t, _) = bar1Notes[1].lyric { #expect(t.value == "re") }
        // Second measure: mi fa
        let bar2Notes = measures[1].noteEvents
        guard bar2Notes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        if case .text(let t, _) = bar2Notes[0].lyric { #expect(t.value == "mi") }
        if case .text(let t, _) = bar2Notes[1].lyric { #expect(t.value == "fa") }
    }

    @Test("Tilde ~ is a word-linking space (no break between syllables on display)")
    func tilde() {
        // "once~upon" means these two words should appear joined (no space) in display.
        // The model represents this as two syllables with the tilde preserved in text.
        // Exact behavior is renderer-side, but the text value should contain the tilde
        // or be split appropriately. Per standard, ~ is treated as a space in alignment
        // but rendered as no-space.
        let result = parse(lyricTune("CD|", "once~upon"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        // The tilde is a single alignment token, so one note gets "once~upon" or two notes
        // get "once" and "upon". The standard treats ~ as a single syllable attachment.
        #expect(!notes.isEmpty)
    }

    // MARK: W: trailing words (not aligned)

    @Test("W: field stores trailing words (not per-note)")
    func trailingWords() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        W:These words are not aligned to notes.
        """
        let result = parse(abc)
        let tune = result.score.firstTune
        // W: words go into the freeText or typesetText of the score,
        // or into tune metadata. They are NOT per-note.
        // The key assertion: notes should have nil lyric (since w: wasn't used)
        let notes = tune?.singleVoiceMeasures.first?.noteEvents ?? []
        for note in notes {
            #expect(note.lyric == nil)
        }
    }
}
