//
//  Measure.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Measure {
    public let openingBar: BarLine?              // bar before first event (e.g. anacrusis end)
    public let events: [Event]                   // notes, rests, chords, grace groups, ties, …
    public let closingBar: BarLine               // bar at end; may carry repeat info
    public let endingNumber: [Int]?              // |1, |2, [1,2 variant endings
    public let source: SourceRange
}
