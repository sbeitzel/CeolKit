//
//  Dialect.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum Dialect: Sendable {
    case strict(version: String)
    case loose // pre-2.1 or unversioned
}

extension Dialect {
    static let v2_1: Self = .strict(version: "2.1")
    static let v2_2: Self = .strict(version: "2.2")
}
