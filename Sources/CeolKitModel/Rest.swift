//
//  Rest.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Rest: Sendable {
    public let kind: RestKind
    /// In unit note lengths (same normalisation as `Note.duration`) — except for a
    /// full-measure rest (`Z`, `X`), whose duration is the number of measures it stands for,
    /// as written: `Z6` is `6/1` whatever `L:` is.  Read that through ``measureCount``.
    public let duration: Fraction
    public let decorations: [Decoration]
    public let source: SourceRange

    public init(kind: RestKind, duration: Fraction, decorations: [Decoration], source: SourceRange) {
        self.kind = kind
        self.duration = duration
        self.decorations = decorations
        self.source = source
    }

    /// How many measures a full-measure rest stands for (ABC v2.2 §4.5): `Z6` is six bars'
    /// rest, `Z` and `Z1` one.  `nil` for a rest that is not a full-measure rest.
    ///
    /// Never less than one: a count that rounds to nothing (`Z0`, `Z/2`) is one measure.
    public var measureCount: Int? {
        switch kind {
        case .fullMeasure, .fullMeasureInvisible:
            guard duration.denominator != 0 else { return 1 }
            let count = (Double(duration.numerator) / Double(duration.denominator)).rounded()
            return count >= 1 ? Int(exactly: count) ?? 1 : 1
        case .normal, .invisible:
            return nil
        }
    }
}

public enum RestKind: Sendable {
    case normal          // z — visible, counts duration
    case invisible       // x — invisible, counts duration
    case fullMeasure     // Z — visible whole-bar rest; `Zn` is n bars' rest (`Rest.measureCount`)
    case fullMeasureInvisible  // X — invisible whole-bar rest; `Xn` likewise
}
