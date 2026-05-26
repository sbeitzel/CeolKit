//
//  TieState.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum TieState: Hashable, Sendable {
    case none            // not part of a tie
    case startsTie       // tied forward only (first note of a chain)
    case continuesTie    // tied both backward and forward (mid-chain)
    case endsTie         // tied backward only (last note of a chain)
}
