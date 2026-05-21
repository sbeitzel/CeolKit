import CeolKitModel

/// Aligns lyric tokens from a `w:` field to note events in the corresponding music line.
///
/// Alignment rules (ABC v2.2 §6):
/// - Each syllable token consumes the next note.
/// - `_` (melisma) extends the previous syllable (does not consume a new note, marks as .melisma).
/// - `*` (skip) consumes a note without attaching text.
/// - `|` resets the note pointer to match bar lines (treated as a no-op here; bar alignment
///   is handled by the caller if needed).
/// - Spaces and hyphens between syllables separate words; `.hyphen` connection is set
///   when the source syllable ended with `-`.
struct LyricAligner {
    static func align(tokens: [LyricToken], to events: [Event]) -> [Event] {
        var result = events
        var noteIdx = 0  // index into result, pointing at the next note to fill

        func advanceToNote() -> Int? {
            while noteIdx < result.count {
                switch result[noteIdx] {
                case .note, .chord: return noteIdx
                default: noteIdx += 1
                }
            }
            return nil
        }

        for token in tokens {
            switch token {
            case .syllable(let text, let connection):
                guard let idx = advanceToNote() else { break }
                let syllable = LyricSyllable.text(
                    TextString(value: text, source: dummySource),
                    connection: connection
                )
                result[idx] = withLyric(syllable, result[idx])
                noteIdx += 1

            case .melisma:
                guard let idx = advanceToNote() else { break }
                result[idx] = withLyric(.melisma, result[idx])
                noteIdx += 1

            case .skip:
                guard let idx = advanceToNote() else { break }
                result[idx] = withLyric(.skip, result[idx])
                noteIdx += 1

            case .barReset:
                // Advance noteIdx past the next bar line to re-sync with the bar structure.
                while noteIdx < result.count {
                    if case .note = result[noteIdx] { break }
                    if case .chord = result[noteIdx] { break }
                    noteIdx += 1
                }
            }
        }
        return result
    }

    private static var dummySource: SourceRange {
        SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
    }

    private static func withLyric(_ lyric: LyricSyllable, _ event: Event) -> Event {
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
                beam: n.beam,
                lyric: lyric,
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
                ties: c.ties,
                slurs: c.slurs,
                lyric: lyric,
                source: c.source
            ))
        default:
            return event
        }
    }
}
