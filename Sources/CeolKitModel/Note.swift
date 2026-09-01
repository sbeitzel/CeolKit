//
//  Note.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Note: Sendable {
    public let pitch: Pitch                // diatonic + chromatic resolved
    public let writtenAccidental: Alteration? // what was actually printed in source
    public let displayedAccidental: Alteration? // what should be printed (after key sig & bar scope)
    public let duration: Fraction          // multiplied by unitNoteLength to get a whole-note fraction
    public let ties: TieState              // .none / .startsTie / .continuesTie / .endsTie
    public let slurs: SlurState            // open count, close count
    public let decorations: [Decoration]
    public let chordSymbol: ChordSymbol?
    public let annotations: [Annotation]
    public let beam: BeamState             // .start / .middle / .end / .single
    /// The syllables the `w:` lines following this note's music line aligned to it, one
    /// entry per verse in source order: `lyrics[0]` belongs to the first `w:` line.
    ///
    /// A `nil` entry means that verse's line was exhausted before it reached this note
    /// (§10 open question 5) — which `.skip`, a verse that reached the note and passed
    /// over it with `*`, is deliberately not. Trailing `nil`s are trimmed, so a note no
    /// verse reaches carries an empty array.
    public let lyrics: [LyricSyllable?]
    public let source: SourceRange

    /// The first verse's syllable — the whole answer for the great majority of tunes,
    /// which carry at most one `w:` line per music line.
    public var lyric: LyricSyllable? { lyrics.first ?? nil }

    public init(
        pitch: Pitch,
        writtenAccidental: Alteration?,
        displayedAccidental: Alteration?,
        duration: Fraction,
        ties: TieState,
        slurs: SlurState,
        decorations: [Decoration],
        chordSymbol: ChordSymbol?,
        annotations: [Annotation],
        beam: BeamState,
        lyrics: [LyricSyllable?],
        source: SourceRange
    ) {
        self.pitch = pitch
        self.writtenAccidental = writtenAccidental
        self.displayedAccidental = displayedAccidental
        self.duration = duration
        self.ties = ties
        self.slurs = slurs
        self.decorations = decorations
        self.chordSymbol = chordSymbol
        self.annotations = annotations
        self.beam = beam
        self.lyrics = LyricSyllable.trimmingVerses(lyrics)
        self.source = source
    }

    /// Convenience for the single-verse case: `lyric` becomes the note's only verse.
    public init(
        pitch: Pitch,
        writtenAccidental: Alteration?,
        displayedAccidental: Alteration?,
        duration: Fraction,
        ties: TieState,
        slurs: SlurState,
        decorations: [Decoration],
        chordSymbol: ChordSymbol?,
        annotations: [Annotation],
        beam: BeamState,
        lyric: LyricSyllable?,
        source: SourceRange
    ) {
        self.init(
            pitch: pitch,
            writtenAccidental: writtenAccidental,
            displayedAccidental: displayedAccidental,
            duration: duration,
            ties: ties,
            slurs: slurs,
            decorations: decorations,
            chordSymbol: chordSymbol,
            annotations: annotations,
            beam: beam,
            lyrics: lyric.map { [$0] } ?? [],
            source: source
        )
    }
}
