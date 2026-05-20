//
//  Note.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Note {
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
}
