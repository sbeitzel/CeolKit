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
    /// Whether the field said `octave=` at all.  An `octave=` lasts until another replaces it
    /// (§4.6), so a field that does not state one leaves the voice's alone — and `octave=0`,
    /// which does state one, puts it back to none.  Only this tells the two apart.
    public let statesOctave: Bool

    public init(semitones: Int, octave: Int, statesOctave: Bool = false) {
        self.semitones = semitones
        self.octave = octave
        self.statesOctave = statesOctave || octave != 0
    }

    public static let none = Transposition(semitones: 0, octave: 0)
}
