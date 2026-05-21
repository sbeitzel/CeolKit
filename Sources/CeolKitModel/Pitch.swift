//
//  Pitch.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Pitch: Hashable {
    public let step: DiatonicStep          // .c .d .e .f .g .a .b
    public let alteration: Alteration      // exact, rational; see below
    public let octave: Int                 // scientific-pitch-notation octave (middle C = 4)

    public init(step: DiatonicStep, alteration: Alteration, octave: Int) {
        self.step = step
        self.alteration = alteration
        self.octave = octave
    }
}

/// A pitch class: letter + alteration without an octave.
/// Used wherever octave is irrelevant — key signature tonic, chord symbol root, slash-chord bass.
public struct PitchClass: Hashable {
    public let step: DiatonicStep
    public let alteration: Alteration      // .natural for plain letters; .sharp / .flat for # / b

    public init(step: DiatonicStep, alteration: Alteration) {
        self.step = step
        self.alteration = alteration
    }
}
