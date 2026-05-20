//
//  Tuplet.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Tuplet {
    public let p: Int                    // notes played…
    public let q: Int                    // …in the time of q normal notes
    public let r: Int                    // total notes in the group (may equal p)
    public let events: [Event]           // the r contained events
    public let source: SourceRange
}
