//
//  Tuplet.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Tuplet: Sendable {
    public let p: Int                    // notes played…
    public let q: Int                    // …in the time of q normal notes
    public let r: Int                    // total notes in the group (may equal p)
    public let events: [Event]           // the r contained events
    public let source: SourceRange

    public init(p: Int, q: Int, r: Int, events: [Event], source: SourceRange) {
        self.p = p
        self.q = q
        self.r = r
        self.events = events
        self.source = source
    }
}
