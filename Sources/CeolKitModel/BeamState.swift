//
//  BeamState.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum BeamState: Hashable, Sendable {
    case start    // first note in a beamed group
    case middle   // interior note in a beamed group
    case end      // last note in a beamed group
    case single   // not beamed (duration ≥ unitNoteLength, or isolated beamable note)
}
