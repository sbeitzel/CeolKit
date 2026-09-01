import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #81: the `&` voice overlay of ABC v2.2 §7.4.
///
/// `&` used to reach the semantic pass as an unrecognised character, so the music after it
/// was appended to the bar it was supposed to overlay and `Staff.overlays` was always empty.
/// It is a temporary voice now, wound back over as many bar lines as there were `&`s, and
/// squared off against the stave so a renderer can put it on the same staff.
@Suite("& voice overlay")
struct VoiceOverlayTests {

    private func parse(_ body: String) -> ParseResult {
        CeolKitParser().parse("""
        X:1
        M:6/8
        L:1/8
        K:C
        \(body)
        """, options: .default)
    }

    private func voice(_ body: String) -> Voice {
        parse(body).score.tunes[0].voices[0]
    }

    /// The number of sounding events in each measure — noteheads, rests and the like, with
    /// the spacers a space between notes leaves behind left out.
    private func shape(_ measures: [Measure]) -> [Int] {
        measures.map { measure in
            measure.events.count {
                switch $0 {
                case .note, .chord, .rest, .tuplet: true
                default: false
                }
            }
        }
    }

    // MARK: - The standard's own examples

    @Test("§7.4: two &s on one line make two temporary voices over the bar they follow")
    func specExampleOne() {
        let voice = voice("""
        A2 | c d e f g  a  &\\
             A A A A A  A  &\\
             F E D C B, A, |]
        """)

        #expect(voice.staves.count == 1)
        let stave = voice.staves[0]
        #expect(shape(stave.measures) == [1, 6])
        #expect(stave.overlays.count == 2)
        // Neither overlay says anything in the first bar: the `&`s wound back only as far as
        // the bar the notes before them were in.
        #expect(shape(stave.overlays[0].measures) == [0, 6])
        #expect(shape(stave.overlays[1].measures) == [0, 6])
    }

    @Test("§7.4: && on its own line overlays the two bars of the line above it")
    func specExampleTwo() {
        let voice = voice("""
            g4 f4 | e6 e2 |
        && (d8    | c6) c2|
        """)

        // One stave, not two: the `&&` line is the line above it, overlaid.
        #expect(voice.staves.count == 1)
        let stave = voice.staves[0]
        #expect(shape(stave.measures) == [2, 2])
        #expect(stave.overlays.count == 1)
        #expect(shape(stave.overlays[0].measures) == [1, 2])
    }

    @Test("§7.4: w: matches the notes disregarding the overlay")
    func lyricsIgnoreTheOverlay() {
        let voice = voice("""
            g4 f4 | e6 e2 |
        && (d8    | c6) c2|
        w: ha-la-| lu-yoh
        """)
        let syllables = text(in: voice.staves[0].measures)
        #expect(syllables == ["ha", "la", "lu", "yoh"])

        // And nothing landed on the overlay, which is the half of the rule that would go
        // unnoticed: the syllables would still read correctly above.
        let overlaid = text(in: voice.staves[0].overlays[0].measures)
        #expect(overlaid.isEmpty)
    }

    /// The syllables `w:` put on the notes of `measures`, in order.
    private func text(in measures: [Measure]) -> [String] {
        measures.flatMap { $0.events }.compactMap { event in
            guard case .note(let note) = event, case .text(let string, _) = note.lyric else {
                return nil
            }
            return string.value
        }
    }

    // MARK: - Winding the clock back

    @Test("an & mid-bar overlays the bar it is in, not the one before")
    func windsBackToTheOpenBar() {
        let stave = voice("C D E | F G A & c e g |").staves[0]
        #expect(shape(stave.measures) == [3, 3])
        #expect(shape(stave.overlays[0].measures) == [0, 3])
    }

    @Test("an & straight after a bar line overlays the bar that line closed")
    func windsBackOverTheBarLine() {
        let stave = voice("C D E | & c e g |").staves[0]
        #expect(shape(stave.measures) == [3])
        #expect(shape(stave.overlays[0].measures) == [3])
    }

    @Test("one & on each of two lines is one temporary voice, not two")
    func layersAreReopenedNotRemade() {
        let voice = voice("""
        C D E & c e g |
        F G A & d f a |
        """)
        #expect(voice.staves.count == 2)
        let oneEach = voice.staves.allSatisfy { $0.overlays.count == 1 }
        #expect(oneEach)
        #expect(shape(voice.staves[0].overlays[0].measures) == [3])
        #expect(shape(voice.staves[1].overlays[0].measures) == [3])
    }

    @Test("A leading & opens the next layer, so three lines make the three parts one line does")
    func leadingAmpersandsStack() {
        let split = voice("""
        A2 | cdefga |]
           & AAAAAA |]
           & FEDCB,A, |]
        """)
        let joined = voice("""
        A2 | cdefga &\
             AAAAAA &\
             FEDCB,A, |]
        """)
        #expect(split.staves.count == 1)
        #expect(shape(split.staves[0].measures) == shape(joined.staves[0].measures))
        #expect(split.staves[0].overlays.count == 2)
        #expect(shape(split.staves[0].overlays[0].measures) == [0, 6])
        #expect(shape(split.staves[0].overlays[1].measures) == [0, 6])
    }

    // MARK: - The overlay is its own voice

    @Test("an accidental in an overlay does not reach the voice under it")
    func accidentalsAreScopedToTheLayer() {
        let stave = voice("^FF & =FF |").staves[0]
        func sounding(_ events: [Event]) -> [Alteration] {
            events.compactMap { if case .note(let n) = $0 { n.pitch.alteration } else { nil } }
        }
        // §4.2 scopes an accidental to the bar in the voice that wrote it, and a temporary
        // voice is a voice: the overlay's `=F` says nothing about the `F` above it, and the
        // `^F` above says nothing about the overlay's.
        #expect(sounding(stave.measures[0].events) == [.sharp, .sharp])
        #expect(sounding(stave.overlays[0].measures[0].events) == [.natural, .natural])
    }

    @Test("an overlay's notes are beamed among themselves")
    func beamsStayWithinTheLayer() {
        let stave = voice("CDE & ceg |").staves[0]
        func beams(_ events: [Event]) -> [BeamState] {
            events.compactMap { if case .note(let n) = $0 { n.beam } else { nil } }
        }
        #expect(beams(stave.measures[0].events) == [.start, .middle, .end])
        #expect(beams(stave.overlays[0].measures[0].events) == [.start, .middle, .end])
    }

    // MARK: - Recovery

    @Test("an overlay longer than the music it overlays is diagnosed, and still printed")
    func tooLongIsDiagnosed() {
        let result = parse("C D E | F G A & c e g | d f a |")
        let overlay = result.score.tunes[0].voices[0].staves[0].overlays[0]
        #expect(result.diagnostics.contains { $0.code == .voiceOverlayTooLong })
        // Three bars now, because the overlay claimed one the voice never wrote.
        #expect(shape(result.score.tunes[0].voices[0].staves[0].measures) == [3, 3, 0])
        #expect(shape(overlay.measures) == [0, 3, 3])
    }

    @Test("an & with no bar to wind back to is diagnosed, and starts at the first bar")
    func withoutABarIsDiagnosed() {
        let result = parse("& c e g |")
        let stave = result.score.tunes[0].voices[0].staves[0]
        #expect(result.diagnostics.contains { $0.code == .voiceOverlayWithoutBar })
        #expect(shape(stave.overlays[0].measures) == [3])
    }

    @Test("& is not a reserved character")
    func notAReservedCharacter() {
        let result = parse("C D E & c e g |")
        #expect(!result.diagnostics.contains { $0.code == .reservedCharacter })
    }

    @Test("a tune with no & has no overlays at all")
    func nothingChangesWithoutOne() {
        let voice = voice("C D E | F G A |")
        let bare = voice.staves.allSatisfy { $0.overlays.isEmpty }
        #expect(bare)
        #expect(shape(voice.staves[0].measures) == [3, 3])
    }
}
