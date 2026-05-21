//
//  Transposition.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Transposition: Hashable, Sendable {
    public let semitones: Int    // chromatic transposition; 0 = none
    public let octave: Int       // additional octave shift; 0 = none

    public init(semitones: Int, octave: Int) {
        self.semitones = semitones
        self.octave = octave
    }

    public static let none = Transposition(semitones: 0, octave: 0)
}
