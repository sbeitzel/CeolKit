//
//  SlurState.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct SlurState: Hashable, Sendable {
    public let opens: Int    // slurs beginning at this note
    public let closes: Int   // slurs ending at this note

    public init(opens: Int, closes: Int) {
        self.opens = opens
        self.closes = closes
    }

    public static let none = SlurState(opens: 0, closes: 0)
}
