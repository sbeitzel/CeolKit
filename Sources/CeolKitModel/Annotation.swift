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
}
