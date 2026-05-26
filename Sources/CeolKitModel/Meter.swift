//
//  Meter.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum Meter: Sendable {
    case fraction(num: Int, den: Int)
    case commonTime           // C  -> 4/4
    case cutTime              // C| -> 2/2
    case complex([Int], den: Int)  // (2+3+2)/8
    case free                 // M:none
}
