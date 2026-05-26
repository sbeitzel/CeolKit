//
//  Rest.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Rest: Sendable {
    public let kind: RestKind
    public let duration: Fraction        // in unit note lengths (same normalisation as Note.duration)
    public let decorations: [Decoration]
    public let source: SourceRange

    public init(kind: RestKind, duration: Fraction, decorations: [Decoration], source: SourceRange) {
        self.kind = kind
        self.duration = duration
        self.decorations = decorations
        self.source = source
    }
}

public enum RestKind: Sendable {
    case normal          // z — visible, counts duration
    case invisible       // x — invisible, counts duration
    case fullMeasure     // Z — visible whole-bar rest
    case fullMeasureInvisible  // X — invisible whole-bar rest
}
