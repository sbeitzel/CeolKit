//
//  Annotation.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Annotation: Hashable {
    public let position: AnnotationPosition
    public let text: TextString
    public let source: SourceRange
}

public enum AnnotationPosition: Hashable {
    case above                           // ^
    case below                           // _
    case left                            // <
    case right                           // >
    case absolute(x: Double, y: Double)  // @x,y  (staff-space coordinates)
}
