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
    func resolve(_ events: [Event]) -> [Event] {
        // Collect indices of beamable events and space breaks.
        // Strategy: walk groups delimited by spaces; within each group, assign start/middle/end/single.
        var result = events

        var groupStart: Int? = nil

        func closeGroup(at end: Int) {
            guard let start = groupStart else { return }
            let indices = (start...end).filter { isBeamableIndex($0, in: result) }
            if indices.count == 1 {
                result[indices[0]] = withBeam(.single, result[indices[0]])
            } else if indices.count > 1 {
                result[indices.first!] = withBeam(.start, result[indices.first!])
                for idx in indices.dropFirst().dropLast() {
                    result[idx] = withBeam(.middle, result[idx])
                }
                result[indices.last!] = withBeam(.end, result[indices.last!])
            }
            groupStart = nil
        }

        for i in 0..<result.count {
            switch result[i] {
            case .note, .chord:
                if isBeamable(result[i]) {
                    if groupStart == nil { groupStart = i }
                } else {
                    closeGroup(at: i - 1)
                    result[i] = withBeam(.single, result[i])
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

    private func isBeamableIndex(_ i: Int, in events: [Event]) -> Bool {
        isBeamable(events[i])
    }

    private func isBeamable(_ event: Event) -> Bool {
        switch event {
        case .note(let n):
            return isBeamableDuration(n.duration)
        case .chord(let c):
            return isBeamableDuration(c.duration)
        default:
            return false
        }
    }

    private func isBeamableDuration(_ dur: Fraction) -> Bool {
        // dur is in UNL units.  Beamable iff dur * unitNoteLength < 1/4
        // ↔ 4 * dur.num * unitLen.num < dur.den * unitLen.den
        let ul = unitNoteLength
        return 4 * dur.numerator * ul.numerator < dur.denominator * ul.denominator
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
