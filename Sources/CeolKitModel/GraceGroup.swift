//
//  GraceGroup.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct GraceGroup: Sendable {
    public let kind: GraceKind
    public let notes: [Note]             // durations nominal; timing resolved by renderer
    public let source: SourceRange

    public init(kind: GraceKind, notes: [Note], source: SourceRange) {
        self.kind = kind
        self.notes = notes
        self.source = source
    }
}

public enum GraceKind: Sendable {
    case acciaccatura    // {/  — crushed grace, typically slurred+crossed
    case appoggiatura    // {   — leaning grace
}
