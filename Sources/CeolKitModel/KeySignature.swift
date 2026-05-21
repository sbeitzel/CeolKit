//
//  KeySignature.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct KeySignature {
    public let tonic: PitchClass?          // nil for K:none and K:HP
    public let mode: Mode
    public let modifications: [KeyModification]  // K:D Phr ^f
    public let explicit: Bool              // K: ... exp ...
    public let clef: ClefSpec              // resolved
    public let transposition: Transposition // resolved
    public let staffProperties: StaffProperties
    public let source: SourceRange

    public init(tonic: PitchClass?, mode: Mode, modifications: [KeyModification], explicit: Bool, clef: ClefSpec,
                transposition: Transposition, staffProperties: StaffProperties, source: SourceRange) {
        self.tonic = tonic
        self.mode = mode
        self.modifications = modifications
        self.explicit = explicit
        self.clef = clef
        self.transposition = transposition
        self.staffProperties = staffProperties
        self.source = source
    }
}
