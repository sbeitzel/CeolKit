//
//  Annotation.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Annotation: Hashable, Sendable {
    public let position: AnnotationPosition
    public let text: TextString
    public let source: SourceRange

    public init(position: AnnotationPosition, text: TextString, source: SourceRange) {
        self.position = position
        self.text = text
        self.source = source
    }
}

public enum AnnotationPosition: Hashable, Sendable {
    case above                           // ^
    case below                           // _
    case left                            // <
    case right                           // >
    case absolute(x: Double, y: Double)  // @x,y  (staff-space coordinates)
    /// Quoted text with no placement prefix that is not a chord symbol — `"Fine"`,
    /// `"repeat of part 2"`.  §4.18 reads unprefixed text as a chord, but asks for chord
    /// symbols to be treated "quite liberally", and abcm2ps prints such text as written on
    /// the chord-symbol line.  It is kept here rather than as a ``ChordSymbol`` so that
    /// nothing plays or transposes it (issue #177).
    case chordLine
}
