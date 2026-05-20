//
//  StemDirection.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum StemDirection: Hashable {
    case up
    case down
    case auto                            // default — renderer decides based on note position
}
