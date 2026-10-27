import CeolKitModel

/// Where a tuplet's events stand in the measure they were opened out into, and the ratio it
/// was written with.
///
/// The model keeps a tuplet as one ``Event/tuplet(_:)`` holding its notes, which is the
/// right shape for everything that only needs to know how long it lasts.  Drawing it is not
/// that: its notes take columns, beams, ties and slurs exactly as any other notes do, so the
/// sizer opens every tuplet out into the bar (#231) and keeps this to say which of the bar's
/// events were in it — for the number drawn over them, and for the lengths their noteheads
/// show.
public struct TupletSpan: Sendable, Equatable {
    /// Indices into the measure's events, in order.  Contiguous in a bar sized on its own; a
    /// shared staff interleaves its voices, so another voice's events can stand between them.
    public let eventIndices: [Int]
    /// The number drawn over the group.
    public let p: Int
    public let q: Int

    public init(eventIndices: [Int], p: Int, q: Int) {
        self.eventIndices = eventIndices
        self.p = p
        self.q = q
    }
}

enum TupletExpansion {
    /// `measure` with every tuplet replaced by its own events, and the span each one became.
    ///
    /// The events keep the durations the parser gave them — already scaled by `q/p`, so they
    /// are spaced and timed for how long they sound.  The emitter shows the written length.
    static func expand(_ measure: Measure) -> (measure: Measure, tuplets: [TupletSpan]) {
        guard measure.events.contains(where: { if case .tuplet = $0 { true } else { false } })
        else { return (measure, []) }

        var events: [Event] = []
        var tuplets: [TupletSpan] = []
        var moved: [Int: Int] = [:]
        for (index, event) in measure.events.enumerated() {
            moved[index] = events.count
            guard case .tuplet(let t) = event else {
                events.append(event)
                continue
            }
            let start = events.count
            events += t.events
            if events.count > start {
                tuplets.append(TupletSpan(eventIndices: Array(start..<events.count),
                                          p: t.p, q: t.q))
            }
        }
        moved[measure.events.count] = events.count

        return (Measure(openingBar: measure.openingBar, events: events,
                        closingBar: measure.closingBar,
                        endings: measure.endings(movedBy: moved), source: measure.source,
                        meter: measure.meter, key: measure.key,
                        unitNoteLength: measure.unitNoteLength),
                tuplets)
    }

    /// `event` with the length it was written with rather than the one it sounds: what its
    /// notehead, flag, dot and beams show.  The parser scaled a tuplet's notes, chords and
    /// rests by `q/p`; this scales them back.  A chord's own notes were never scaled.
    static func written(_ event: Event, in tuplet: TupletSpan) -> Event {
        func unscaled(_ d: Fraction) -> Fraction {
            reduced(d.numerator * tuplet.p, d.denominator * tuplet.q)
        }
        switch event {
        case .note(let n):
            return .note(Note(
                pitch: n.pitch, writtenAccidental: n.writtenAccidental,
                displayedAccidental: n.displayedAccidental, duration: unscaled(n.duration),
                ties: n.ties, slurs: n.slurs, decorations: n.decorations,
                chordSymbol: n.chordSymbol, annotations: n.annotations, beam: n.beam,
                lyrics: n.lyrics, source: n.source))
        case .chord(let c):
            return .chord(Chord(
                notes: c.notes, duration: unscaled(c.duration), decorations: c.decorations,
                chordSymbol: c.chordSymbol, annotations: c.annotations, beam: c.beam,
                ties: c.ties, slurs: c.slurs, lyrics: c.lyrics, source: c.source))
        case .rest(let r):
            return .rest(Rest(kind: r.kind, duration: unscaled(r.duration),
                              decorations: r.decorations, source: r.source))
        default:
            return event
        }
    }

    private static func reduced(_ numerator: Int, _ denominator: Int) -> Fraction {
        var (a, b) = (abs(numerator), abs(denominator))
        while b != 0 { (a, b) = (b, a % b) }
        let divisor = max(a, 1)
        return Fraction(numerator: numerator / divisor, denominator: denominator / divisor)
    }
}
