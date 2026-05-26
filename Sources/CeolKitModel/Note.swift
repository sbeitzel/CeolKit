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
    public let lyric: LyricSyllable?       // alignment from w: lines
    public let source: SourceRange

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
        self.lyric = lyric
        self.source = source
    }
}
