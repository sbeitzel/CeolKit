//
//  Chord.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Chord {
    public let notes: [Note]             // ≥2; each Note.duration equals Chord.duration
    public let duration: Fraction
    public let decorations: [Decoration]
    public let chordSymbol: ChordSymbol?
    public let annotations: [Annotation]
    public let beam: BeamState
    public let ties: TieState
    public let slurs: SlurState
    public let lyric: LyricSyllable?
    public let source: SourceRange

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
        self.notes = notes
        self.duration = duration
        self.decorations = decorations
        self.chordSymbol = chordSymbol
        self.annotations = annotations
        self.beam = beam
        self.ties = ties
        self.slurs = slurs
        self.lyric = lyric
        self.source = source
    }
}

/// A harmony symbol written in double quotes above the staff (e.g. `"Gm7"`, `"C/E"`).
/// `root` and `bassNote` are structured for transposition; `quality` is kept verbatim
/// because chord quality vocabulary is not standardised.
public struct ChordSymbol: Hashable {
    public let root: PitchClass          // e.g. G in "Gm7"
    public let quality: String           // e.g. "m7"; empty string for plain major
    public let bassNote: PitchClass?     // slash-chord bass, e.g. E in "C/E"
    public let raw: String               // verbatim text between the quotes
    public let source: SourceRange

    public init(root: PitchClass, quality: String, bassNote: PitchClass?, raw: String, source: SourceRange) {
        self.root = root
        self.quality = quality
        self.bassNote = bassNote
        self.raw = raw
        self.source = source
    }
}
