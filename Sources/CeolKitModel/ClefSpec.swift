//
//  ClefSpec.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct ClefSpec: Hashable, Sendable {
    public let clef: Clef
    public let octaveShift: Int    // 0, ±8, ±15 — as written in source (e.g. treble+8)

    public init(clef: Clef, octaveShift: Int) {
        self.clef = clef
        self.octaveShift = octaveShift
    }
}

public enum Clef: Hashable, Sendable {
    case treble
    case bass
    case baritone      // bass3 — F clef on line 3
    case alto          // C clef on line 3
    case tenor         // C clef on line 4
    case soprano       // C clef on line 1
    case mezzoSoprano  // C clef on line 2
    case percussion    // perc
    case none
}
