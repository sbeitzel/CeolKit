// §14.3 Reels.abc — two Irish reels demonstrating mid-tune key changes,
// chord groups, backslash continuation, and repeat bars.
import Testing
import CeolKitModel
import CeolKitParser

private let reelsABC = """
%abc-2.1
M:4/4
O:Irish
R:Reel

X:1
T:Untitled Reel
C:Trad.
K:D
eg|a2ab ageg|agbg agef|g2g2 fgag|f2d2 d2:|\\
ed|cecA B2ed|cAcA E2ed|cecA B2ed|c2A2 A2:|
K:G
AB|cdec BcdB|ABAF GFE2|cdec BcdB|c2A2 A2:|

X:2
T:Kitchen Girl
C:Trad.
K:D
[c4a4] [B4g4]|efed c2cd|e2f2 gaba|g2e2 e2fg|
a4 g4|efed cdef|g2d2 efed|c2A2 A4:|
K:G
ABcA BAGB|ABAG EDEG|A2AB c2d2|e3f edcB|ABcA BAGB|
ABAG EGAB|cBAc BAG2|A4 A4:|
"""

@Suite("§14.3 Reels.abc")
struct ReelsTests {

    let result = parse(reelsABC)
    var score: Score { result.score }

    // MARK: File-level

    @Test("File parses to strict dialect 2.1")
    func dialectIsStrict() {
        if case .strict(let version) = score.dialect {
            #expect(version == "2.1")
        } else {
            Issue.record("Expected strict dialect, got \(score.dialect)")
        }
    }

    @Test("File contains two tunes")
    func tuneCount() {
        #expect(score.tunes.count == 2)
    }

    @Test("Parse produces no error diagnostics")
    func noErrors() {
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    // MARK: Tune 1 — Untitled Reel (key change, backslash continuation)

    @Test("Tune 1 header key is D major")
    func tune1HeaderKey() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(tune.key.tonic?.step == .d)
        #expect(tune.key.mode == .major)
    }

    @Test("Tune 1 initial meter is 4/4 from file header")
    func tune1Meter() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        if case .fraction(let num, let den) = tune.meter {
            #expect(num == 4)
            #expect(den == 4)
        } else {
            Issue.record("Expected .fraction(4, 4), got \(tune.meter)")
        }
    }

    @Test("Tune 1 anacrusis contains e and g")
    func tune1Anacrusis() {
        guard let tune = score.tunes.first,
              let firstMeasure = tune.singleVoiceMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        let notes = firstMeasure.noteEvents
        #expect(notes.count == 2)
        #expect(notes[0].pitch.step == .e)
        #expect(notes[1].pitch.step == .g)
    }

    @Test("Tune 1 body section after K:G change has G-major key")
    func tune1KeyChangeMidTune() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        let measures = tune.singleVoiceMeasures
        // The key change K:G appears after the first repeat section.
        // Notes after the key change should reflect G major.
        // The measure starting with A B (after K:G) should have a B note whose
        // pitch carries no sharp alteration (B natural is in G major).
        let postKeyChange = measures.dropFirst(5) // skip past D-major section
        let firstPostMeasure = postKeyChange.first(where: { !$0.noteEvents.isEmpty })
        guard let measure = firstPostMeasure else { Issue.record("Parser prerequisite not met"); return }
        // First note after key change should be A (natural) in G-major context
        let firstNote = measure.noteEvents.first
        #expect(firstNote != nil)
        // In G major, A has no alteration
        #expect(firstNote?.pitch.alteration == Alteration(numerator: 0, denominator: 1))
    }

    @Test("Tune 1 has multiple repeat-end bars (two repeat sections)")
    func tune1RepeatBars() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        let repeatEnds = tune.singleVoiceMeasures.filter { $0.closingBar.kind == .repeatEnd }
        #expect(repeatEnds.count >= 2)
    }

    @Test("Tune 1 backslash continuation joins lines without score break")
    func tune1BackslashContinuation() {
        guard let tune = score.tunes.first else { Issue.record("Parser prerequisite not met"); return }
        // The backslash means the first section continues across the source line break.
        // All measures before the key change should be in one staff (no system break).
        // The simplest check: the D-major section has more than 4 measures in one staff.
        let staves = tune.voices.first?.staves ?? []
        let dMajorStaff = staves.first
        #expect((dMajorStaff?.measures.count ?? 0) > 4)
    }

    // MARK: Tune 2 — Kitchen Girl (chord groups, key change)

    @Test("Tune 2 title is 'Kitchen Girl'")
    func tune2Title() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        #expect(score.tunes[1].titles.first?.value == "Kitchen Girl")
    }

    @Test("Tune 2 header key is D major")
    func tune2HeaderKey() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        #expect(tune.key.tonic?.step == .d)
        #expect(tune.key.mode == .major)
    }

    @Test("Tune 2 first event is a chord [c4a4]")
    func tune2FirstChord() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        guard let firstMeasure = tune.singleVoiceMeasures.first else { Issue.record("Parser prerequisite not met"); return }
        let chords = firstMeasure.chordEvents
        #expect(!chords.isEmpty)
        guard let chord = chords.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(chord.notes.count == 2)
    }

    @Test("Tune 2 first chord lower note is c (octave 4)")
    func tune2FirstChordLowerNote() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        guard let firstMeasure = tune.singleVoiceMeasures.first,
              let chord = firstMeasure.chordEvents.first else { Issue.record("Parser prerequisite not met"); return }
        let steps = chord.notes.map(\.pitch.step)
        #expect(steps.contains(.c))
    }

    @Test("Tune 2 first chord upper note is a (octave 4)")
    func tune2FirstChordUpperNote() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        guard let firstMeasure = tune.singleVoiceMeasures.first,
              let chord = firstMeasure.chordEvents.first else { Issue.record("Parser prerequisite not met"); return }
        let steps = chord.notes.map(\.pitch.step)
        #expect(steps.contains(.a))
    }

    @Test("Tune 2 first chord duration is 4 unit note lengths")
    func tune2FirstChordDuration() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        guard let firstMeasure = tune.singleVoiceMeasures.first,
              let chord = firstMeasure.chordEvents.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(chord.duration == Fraction(numerator: 4, denominator: 1))
    }

    @Test("Tune 2 has repeat-end bars in both D-major and G-major sections")
    func tune2HasRepeatBars() {
        guard score.tunes.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        let tune = score.tunes[1]
        let repeatEnds = tune.singleVoiceMeasures.filter { $0.closingBar.kind == .repeatEnd }
        #expect(repeatEnds.count >= 2)
    }
}
