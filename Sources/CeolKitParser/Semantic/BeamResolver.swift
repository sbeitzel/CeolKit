import CeolKitModel

/// Assigns BeamState to notes and chords in an event array based on meter and unit note length.
///
/// Beaming rules (ABC v2.2 §4.5):
/// - A note is beamable if its duration is strictly less than the beat unit.
///   Simple meter: beat unit = 1/d. Compound meter (n%3==0, n≥6): beat unit = 3/d.
/// - Consecutive beamable notes with no intervening space are beamed together.
/// - Grace notes are always beamable (rendered beamed regardless of duration).
struct BeamResolver {
    let meter: Meter
    let unitNoteLength: Fraction

    // The beat unit as a whole-note fraction (numerator, denominator).
    private var beatUnit: Fraction {
        switch meter {
        case .fraction(let n, let d):
            if n >= 6 && n % 3 == 0 {
                return Fraction(numerator: 3, denominator: d)
            }
            return Fraction(numerator: 1, denominator: d)
        case .commonTime:
            return Fraction(numerator: 1, denominator: 4)  // 4/4
        case .cutTime:
            return Fraction(numerator: 1, denominator: 2)  // 2/2
        case .complex(let parts, let d):
            // Use the first group's beat unit
            let n = parts.first ?? 2
            if n >= 6 && n % 3 == 0 {
                return Fraction(numerator: 3, denominator: d)
            }
            return Fraction(numerator: 1, denominator: d)
        case .free:
            return unitNoteLength
        }
    }

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
        // dur is in UNL units; beatUnit is a whole-note fraction.
        // Beamable iff dur * unitNoteLength < beatUnit
        // ↔ dur.num * unitLen.num * bu.den < bu.num * dur.den * unitLen.den
        let bu = beatUnit
        let ul = unitNoteLength
        return dur.numerator * ul.numerator * bu.denominator
             < bu.numerator * dur.denominator * ul.denominator
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
                beam: beam,
                ties: c.ties,
                slurs: c.slurs,
                lyric: c.lyric,
                source: c.source
            ))
        default:
            return event
        }
    }
}
