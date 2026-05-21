import CeolKitModel

/// Resolves tie chains across an event sequence.
///
/// Notes emitted by the note builder have `.startsTie` when the source had a `-` suffix.
/// This pass finds those notes and marks matching following notes as `.endsTie` or
/// `.continuesTie`.  A "matching note" has the same DiatonicStep and octave; a chord
/// matches any of its constituent notes.
struct TieResolver {
    func resolve(_ events: [Event]) -> [Event] {
        var result = events
        // Check original events (not result) to determine which positions start ties,
        // so that modifying result[j] doesn't affect tie detection at position j.
        var i = 0
        while i < result.count {
            let origStartsTie: Bool
            switch events[i] {
            case .note(let n):  origStartsTie = (n.ties == .startsTie)
            case .chord(let c): origStartsTie = (c.ties == .startsTie)
            default:            origStartsTie = false
            }

            if origStartsTie {
                switch result[i] {
                case .note(let n):
                    if let j = nextMatchingNote(after: i, step: n.pitch.step, octave: n.pitch.octave, in: result) {
                        let successorTie: TieState = origStartsTieAt(j, in: events) ? .continuesTie : .endsTie
                        result[j] = withTie(successorTie, result[j])
                    }
                case .chord(let c):
                    if let j = nextMatchingChord(after: i, notes: c.notes, in: result) {
                        let successorTie: TieState = origStartsTieAt(j, in: events) ? .continuesTie : .endsTie
                        result[j] = withTie(successorTie, result[j])
                    }
                default: break
                }
            }
            i += 1
        }
        return result
    }

    private func origStartsTieAt(_ j: Int, in events: [Event]) -> Bool {
        guard j < events.count else { return false }
        switch events[j] {
        case .note(let n):  return n.ties == .startsTie
        case .chord(let c): return c.ties == .startsTie
        default:            return false
        }
    }

    private func nextMatchingNote(after i: Int, step: DiatonicStep, octave: Int, in events: [Event]) -> Int? {
        for j in (i + 1)..<events.count {
            switch events[j] {
            case .note(let n) where n.pitch.step == step && n.pitch.octave == octave:
                return j
            case .note: continue
            case .chord(let c):
                if c.notes.contains(where: { $0.pitch.step == step && $0.pitch.octave == octave }) {
                    return j
                }
            default: break
            }
        }
        return nil
    }

    private func nextMatchingChord(after i: Int, notes: [Note], in events: [Event]) -> Int? {
        let pairs = notes.map { ($0.pitch.step, $0.pitch.octave) }
        for j in (i + 1)..<events.count {
            switch events[j] {
            case .note(let n):
                if pairs.contains(where: { $0 == n.pitch.step && $1 == n.pitch.octave }) {
                    return j
                }
            case .chord(let c):
                if c.notes.contains(where: { n in
                    pairs.contains(where: { $0 == n.pitch.step && $1 == n.pitch.octave })
                }) {
                    return j
                }
            default: break
            }
        }
        return nil
    }

    private func withTie(_ tie: TieState, _ event: Event) -> Event {
        switch event {
        case .note(let n):
            return .note(Note(
                pitch: n.pitch,
                writtenAccidental: n.writtenAccidental,
                displayedAccidental: n.displayedAccidental,
                duration: n.duration,
                ties: tie,
                slurs: n.slurs,
                decorations: n.decorations,
                chordSymbol: n.chordSymbol,
                annotations: n.annotations,
                beam: n.beam,
                lyric: n.lyric,
                source: n.source
            ))
        case .chord(let c):
            return .chord(Chord(
                notes: c.notes,
                duration: c.duration,
                decorations: c.decorations,
                chordSymbol: c.chordSymbol,
                annotations: c.annotations,
                beam: c.beam,
                ties: tie,
                slurs: c.slurs,
                lyric: c.lyric,
                source: c.source
            ))
        default:
            return event
        }
    }
}
