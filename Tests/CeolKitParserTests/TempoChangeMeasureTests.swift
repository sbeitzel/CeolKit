import Testing
import CeolKitModel
import CeolKitParser

/// Issue #234: a tempo change belongs to the music after it.  One written after a bar's last
/// note, or alone before a bar line, is carried over the bar line to open the next bar —
/// where the renderer draws it over that bar's first note — rather than standing against the
/// end of its own bar or closing a bar of nothing.
@Suite("A tempo change lands on the bar of the music it governs")
struct TempoChangeMeasureTests {

    private func measures(_ body: String) -> [Measure] {
        let abc = ["X:1", "T:Tempo", "M:6/8", "L:1/8", "K:D", body].joined(separator: "\n")
        let score = CeolKitParser().parse(abc, options: .default).score
        return score.tunes[0].voices[0].staves.flatMap(\.measures)
    }

    private func tempoIndices(_ measure: Measure) -> [Int] {
        measure.events.indices.filter {
            if case .tempoChange = measure.events[$0] { return true }
            return false
        }
    }

    /// Whether `event` is music: anything but a spacer or a tempo change.
    private static func isMusic(_ event: Event) -> Bool {
        switch event {
        case .spacer, .tempoChange: return false
        default:                    return true
        }
    }

    private func firstMusic(_ measure: Measure) -> Int? {
        measure.events.firstIndex(where: Self.isMusic)
    }

    @Test("A Q: line before the first bar line makes no bar of its own")
    func tempoLineBeforeOpeningRepeat() throws {
        let bars = measures("Q:118\n|:a3 f2e|dfa b2a|")
        try #require(bars.count == 2)
        let tempos = tempoIndices(bars[0])
        #expect(tempos.count == 1)
        #expect(tempos.allSatisfy { $0 < firstMusic(bars[0])! })
        #expect(tempoIndices(bars[1]).isEmpty)
    }

    @Test("A tempo change written against a bar line opens the bar after it")
    func tempoAtBarEndIsCarried() throws {
        let bars = measures("a3 f2e [Q:1/4=88]|dfa b2a|")
        try #require(bars.count == 2)
        #expect(tempoIndices(bars[0]).isEmpty)
        let tempos = tempoIndices(bars[1])
        #expect(tempos.count == 1)
        #expect(tempos.allSatisfy { $0 < firstMusic(bars[1])! })
    }

    @Test("A tempo change part way through a bar stays where it was written")
    func tempoMidBarStays() throws {
        let bars = measures("a3 f2e|dfa [Q:1/4=88]b2a|")
        try #require(bars.count == 2)
        #expect(tempoIndices(bars[0]).isEmpty)
        let tempos = try #require(tempoIndices(bars[1]).first)
        let notesBefore = bars[1].events[..<tempos].filter(Self.isMusic)
        #expect(notesBefore.count == 3)
    }

    @Test("A tempo change after the voice's last note stays on its last bar")
    func tempoAtTuneEndStays() throws {
        let bars = measures("a3 f2e|dfa b2a [Q:1/4=40]|]")
        try #require(bars.count == 2)
        #expect(tempoIndices(bars[1]).count == 1)
    }
}
