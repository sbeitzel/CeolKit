//
//  Chord.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Chord: Sendable {
    public let notes: [Note]             // ≥2; each Note.duration equals Chord.duration
    public let duration: Fraction
    public let decorations: [Decoration]
    public let chordSymbol: ChordSymbol?
    public let annotations: [Annotation]
    public let beam: BeamState
    public let ties: TieState
    public let slurs: SlurState
    /// The syllables aligned to this chord, one entry per verse; see ``Note/lyrics``.
    public let lyrics: [LyricSyllable?]
    public let source: SourceRange

    /// The first verse's syllable; see ``Note/lyric``.
    public var lyric: LyricSyllable? { lyrics.first ?? nil }

    public init(
        notes: [Note],
        duration: Fraction,
        decorations: [Decoration],
        chordSymbol: ChordSymbol?,
        annotations: [Annotation],
        beam: BeamState,
        ties: TieState,
        slurs: SlurState,
        lyrics: [LyricSyllable?],
        source: SourceRange
    ) {
        self.notes = notes
        self.duration = duration
        self.decorations = decorations
        self.chordSymbol = chordSymbol
        self.annotations = annotations
        self.beam = beam
        self.ties = ties
        self.slurs = slurs
        self.lyrics = LyricSyllable.trimmingVerses(lyrics)
        self.source = source
    }

    /// Convenience for the single-verse case; see ``Note/init(pitch:writtenAccidental:displayedAccidental:duration:ties:slurs:decorations:chordSymbol:annotations:beam:lyric:source:)``.
    public init(
        notes: [Note],
        duration: Fraction,
        decorations: [Decoration],
        chordSymbol: ChordSymbol?,
        annotations: [Annotation],
        beam: BeamState,
        ties: TieState,
        slurs: SlurState,
        lyric: LyricSyllable?,
        source: SourceRange
    ) {
        self.init(
            notes: notes,
            duration: duration,
            decorations: decorations,
            chordSymbol: chordSymbol,
            annotations: annotations,
            beam: beam,
            ties: ties,
            slurs: slurs,
            lyrics: lyric.map { [$0] } ?? [],
            source: source
        )
    }
}

/// A harmony symbol written in double quotes above the staff (e.g. `"Gm7"`, `"C/E"`).
/// `root` and `bassNote` are structured for transposition; `quality` is kept verbatim
/// because chord quality vocabulary is not standardised.
public struct ChordSymbol: Hashable, Sendable {
    public let root: PitchClass          // e.g. G in "Gm7"
    public let quality: String           // e.g. "m7"; empty string for plain major
    public let bassNote: PitchClass?     // slash-chord bass, e.g. E in "C/E"
    public let raw: String               // verbatim text between the quotes
    /// `raw`, trimmed, split where the parser read a character as an accidental — in the
    /// root, the bass note, the type (`"C7b9"`) and an alternate chord (`"G(Bb)"`) — so that
    /// a renderer can draw ♭ and ♯ signs where the source spelled them `b` and `#`, without
    /// having to tell the `b` of `"Bb"` from the one of `"7(b9)"` itself (issue #184).
    public let segments: [Segment]
    public let source: SourceRange

    /// A run of a chord symbol's text: written as it stands, or an accidental to draw as a
    /// sign whatever character spelled it.
    public enum Segment: Hashable, Sendable {
        case text(String)
        case accidental(Alteration)
    }

    /// - Parameter segments: `nil` takes `raw` as one run of text with no accidentals.
    public init(root: PitchClass, quality: String, bassNote: PitchClass?, raw: String,
                segments: [Segment]? = nil, source: SourceRange) {
        self.root = root
        self.quality = quality
        self.bassNote = bassNote
        self.raw = raw
        self.segments = segments ?? [.text(raw)]
        self.source = source
    }
}
