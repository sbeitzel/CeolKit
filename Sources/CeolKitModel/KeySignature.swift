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
}
