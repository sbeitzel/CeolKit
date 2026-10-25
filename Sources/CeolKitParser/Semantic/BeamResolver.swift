import CeolKitModel

/// Assigns BeamState to notes and chords in an event array based on unit note length.
///
/// Beaming rules (ABC v2.2 §4.7):
/// - A note is beamable if it would carry a flag: its length is strictly less than a quarter
///   note, whatever the meter.  "If L:1/8 then ABC2DE is equivalent to AB C2 DE."
/// - Consecutive beamable notes with no intervening space are beamed together.
/// - Grace notes are always beamable (rendered beamed regardless of duration).
struct BeamResolver {
    let unitNoteLength: Fraction

    /// Resolves beam states for a flat event list. Returns a new list with BeamState set on
    /// Note and Chord events. Space elements in the input break beam groups.
    ///
    /// A tuplet's notes are beamed where they stand, with each other and with the notes either
    /// side of the tuplet, as if the `(p` were not there (#231): the groups are found over the
    /// events with every tuplet opened out, and the tuplets are then put back together.
    func resolve(_ events: [Event]) -> [Event] {
        var slots: [Slot] = []
        for (outer, event) in events.enumerated() {
            if case .tuplet(let t) = event {
                for (inner, e) in t.events.enumerated() {
                    slots.append(Slot(event: e, outer: outer, inner: inner, p: t.p, q: t.q))
                }
            } else {
                slots.append(Slot(event: event, outer: outer, inner: nil, p: 1, q: 1))
            }
        }
        let resolved = resolveFlat(slots)

        var result = events
        for (outer, event) in events.enumerated() {
            if case .tuplet(let t) = event {
                let inner = resolved.filter { $0.outer == outer }.map(\.event)
                result[outer] = .tuplet(Tuplet(p: t.p, q: t.q, r: t.r, events: inner,
                                               source: t.source))
            }
        }
        for slot in resolved where slot.inner == nil {
            result[slot.outer] = slot.event
        }
        return result
    }

    /// One event of the measure with its tuplets opened out: where it came from, and the
    /// `p`/`q` of the tuplet it is in — `1`/`1` outside one — which turns the duration the
    /// model stores, already scaled by `q/p`, back into the one that was written.
    private struct Slot {
        var event: Event
        let outer: Int
        let inner: Int?
        let p: Int
        let q: Int
    }

    private func resolveFlat(_ slots: [Slot]) -> [Slot] {
        // Collect indices of beamable events and space breaks.
        // Strategy: walk groups delimited by spaces; within each group, assign start/middle/end/single.
        var result = slots

        var groupStart: Int? = nil

        func closeGroup(at end: Int) {
            guard let start = groupStart else { return }
            let indices = (start...end).filter { isBeamable(result[$0]) }
            if indices.count == 1 {
                result[indices[0]].event = withBeam(.single, result[indices[0]].event)
            } else if indices.count > 1 {
                result[indices.first!].event = withBeam(.start, result[indices.first!].event)
                for idx in indices.dropFirst().dropLast() {
                    result[idx].event = withBeam(.middle, result[idx].event)
                }
                result[indices.last!].event = withBeam(.end, result[indices.last!].event)
            }
            groupStart = nil
        }

        for i in 0..<result.count {
            switch result[i].event {
            case .note, .chord:
                if isBeamable(result[i]) {
                    if groupStart == nil { groupStart = i }
                } else {
                    closeGroup(at: i - 1)
                    result[i].event = withBeam(.single, result[i].event)
                }
            case .spacer:
                closeGroup(at: i - 1)
            case .rest:
                closeGroup(at: i - 1)
                // Rests always break beaming
            default:
                break
            }
        }
        closeGroup(at: result.count - 1)
        return result
    }

    private func isBeamable(_ slot: Slot) -> Bool {
        switch slot.event {
        case .note(let n):
            return isBeamableDuration(n.duration, p: slot.p, q: slot.q)
        case .chord(let c):
            return isBeamableDuration(c.duration, p: slot.p, q: slot.q)
        default:
            return false
        }
    }

    private func isBeamableDuration(_ dur: Fraction, p: Int, q: Int) -> Bool {
        // dur is in UNL units, scaled by q/p inside a tuplet; what was written is dur × p/q.
        // Beamable iff written × unitNoteLength < 1/4
        // ↔ 4 * dur.num * p * unitLen.num < dur.den * q * unitLen.den
        let ul = unitNoteLength
        return 4 * dur.numerator * p * ul.numerator < dur.denominator * q * ul.denominator
    }

    private func withBeam(_ beam: BeamState, _ event: Event) -> Event {
        switch event {
        case .note(let n):
            return .note(Note(
                pitch: n.pitch,
                writtenAccidental: n.writtenAccidental,
                displayedAccidental: n.displayedAccidental,
                duration: n.duration,
                ties: n.ties,
                slurs: n.slurs,
                decorations: n.decorations,
                chordSymbol: n.chordSymbol,
                annotations: n.annotations,
                beam: beam,
                lyrics: n.lyrics,
                source: n.source
            ))
        case .chord(let c):
            return .chord(Chord(
                notes: c.notes,
                duration: c.duration,
                decorations: c.decorations,
                chordSymbol: c.chordSymbol,
                annotations: c.annotations,
                beam: beam,
                ties: c.ties,
                slurs: c.slurs,
                lyrics: c.lyrics,
                source: c.source
            ))
        default:
            return event
        }
    }
}
