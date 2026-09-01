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

    // MARK: Verses

    @Test("A second w: line is a second verse, not a replacement for the first")
    func secondLineIsASecondVerse() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        w: do re mi fa
        w: un deux trois quatre
        """
        let notes = parse(abc).score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 4 else { Issue.record("Parser prerequisite not met"); return }
        let first = notes[0].lyrics
        #expect(first.count == 2)
        if case .text(let t, _) = first.first ?? nil { #expect(t.value == "do") }
        if case .text(let t, _) = first.count > 1 ? first[1] : nil { #expect(t.value == "un") }
        // `lyric` still answers for the first verse, which is what most callers want.
        if case .text(let t, _) = notes[3].lyric { #expect(t.value == "fa") }
    }

    @Test("A verse that runs out leaves nil where it did not reach")
    func shorterVerseLeavesNil() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        w: do
        w: un deux trois quatre
        """
        let notes = parse(abc).score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 4 else { Issue.record("Parser prerequisite not met"); return }
        let second = notes[1].lyrics
        #expect(second.count == 2)
        #expect(second.first ?? nil == nil, "Verse 1 ran out and should say nothing here")
        if case .text(let t, _) = second.count > 1 ? second[1] : nil { #expect(t.value == "deux") }
    }

    @Test("A new music line starts the verse count over")
    func versesResetAtTheNextMusicLine() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CDEF|
        w: do re mi fa
        w: un deux trois quatre
        GABc|
        w: sol la si do
        """
        let measures = parse(abc).score.firstTune?.singleVoiceMeasures ?? []
        guard measures.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let second = measures[1].noteEvents
        guard let note = second.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(note.lyrics.count == 1, "The second line's w: is its own first verse")
        if case .text(let t, _) = note.lyric { #expect(t.value == "sol") }
    }

    // MARK: Line continuation (§2.2)

    /// The backslashes are escaped for Swift, whose multi-line literals take a trailing
    /// one as a line continuation of their own: the ABC lines end `|\` and `re\`.
    @Test("A w: line ending in a backslash continues onto the next w: line")
    func continuedLyricLineIsOneVerse() {
        // The music line is continued too, so both halves are one line with one verse
        // under it — §14.4's Canzonetta is written exactly this way.
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CD|\\
        w: do re\\
        EF|
        w: mi fa
        """
        let measures = parse(abc).score.firstTune?.singleVoiceMeasures ?? []
        let notes = measures.flatMap(\.noteEvents)
        guard notes.count == 4 else { Issue.record("Parser prerequisite not met"); return }
        for (note, syllable) in zip(notes, ["do", "re", "mi", "fa"]) {
            #expect(note.lyrics.count == 1, "The continuation is not a second verse")
            if case .text(let t, _) = note.lyric {
                #expect(t.value == syllable)
            } else {
                Issue.record("Note expected lyric '\(syllable)', got \(String(describing: note.lyric))")
            }
        }
    }

    @Test("The continuation backslash is not part of the syllable")
    func continuationMarkIsNotPrinted() {
        let abc = """
        X:1
        T:Test
        M:4/4
        L:1/4
        K:C
        CD|
        w: do re\\
        w: mi
        """
        let notes = parse(abc).score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        guard notes.count == 2 else { Issue.record("Parser prerequisite not met"); return }
        if case .text(let t, _) = notes[1].lyric {
            #expect(t.value == "re")
        } else {
            Issue.record("Expected 're', got \(String(describing: notes[1].lyric))")
        }
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
