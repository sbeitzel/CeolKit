//
//  KeyModification.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// An explicit accidental modification applied to a diatonic step within a key signature
/// (e.g. the `^f` in `K:D Phr ^f`). Structurally identical to `PitchClass` but
/// semantically distinct: this is an instruction ("alter this step by this amount")
/// rather than a pitch name.
public struct KeyModification: Hashable {
    public let step: DiatonicStep
    public let alteration: Alteration
}
