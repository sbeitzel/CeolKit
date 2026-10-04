//
//  KeySignature.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct KeySignature: Sendable {
    public let tonic: PitchClass?          // nil for K:none and K:HP
    public let mode: Mode
    public let modifications: [KeyModification]  // K:D Phr ^f
    public let explicit: Bool              // K: ... exp ...
    public let clef: ClefSpec              // resolved
    public let transposition: Transposition // resolved
    public let staffProperties: StaffProperties
    public let source: SourceRange
    /// False for a `K:` that names no key — `K:bass`, `K:clef=bass`, an empty `K:` — and
    /// changes only what its options state (§3.1.14, §4.6).
    ///
    /// Only the parser produces `false`.  The semantic pass resolves it before anything
    /// reaches the domain model: in the tune header it becomes `K:none`, and part way through
    /// a voice it takes the key already in force, so a `Tune` or a `Measure` never carries a
    /// key that has not been decided.
    public let statesKey: Bool
    /// False for a `K:` that states no clef, whose `clef` is then only the treble default.
    ///
    /// Resolved like `statesKey`: part way through a voice the clef in force carries on, as
    /// it does in abcm2ps, so `K:D` after `K:bass` changes the key and leaves the bass clef.
    public let statesClef: Bool

    public init(tonic: PitchClass?, mode: Mode, modifications: [KeyModification], explicit: Bool, clef: ClefSpec,
                transposition: Transposition, staffProperties: StaffProperties, source: SourceRange,
                statesKey: Bool = true, statesClef: Bool = true) {
        self.tonic = tonic
        self.mode = mode
        self.modifications = modifications
        self.explicit = explicit
        self.clef = clef
        self.transposition = transposition
        self.staffProperties = staffProperties
        self.source = source
        self.statesKey = statesKey
        self.statesClef = statesClef
    }
}
