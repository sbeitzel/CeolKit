//
//  Tempo.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Tempo {
    public let prelude: TextString?
    public let beats: [Fraction]   // one or more beat units
    public let bpm: Double
    public let postlude: TextString?

    public init(prelude: TextString?, beats: [Fraction], bpm: Double, postlude: TextString?) {
        self.prelude = prelude
        self.beats = beats
        self.bpm = bpm
        self.postlude = postlude
    }
}
