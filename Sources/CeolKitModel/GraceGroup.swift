//
//  GraceGroup.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct GraceGroup {
    public let kind: GraceKind
    public let notes: [Note]             // durations nominal; timing resolved by renderer
    public let source: SourceRange
}

public enum GraceKind {
    case acciaccatura    // {/  — crushed grace, typically slurred+crossed
    case appoggiatura    // {   — leaning grace
}
