//
//  DiatonicStep.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum DiatonicStep: Int, CaseIterable, Hashable, Comparable, Sendable {
    public static func < (lhs: DiatonicStep, rhs: DiatonicStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    case c = 0
    case d = 1
    case e = 2
    case f = 3
    case g = 4
    case a = 5
    case b = 6
}
