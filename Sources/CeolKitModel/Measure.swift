//
//  Measure.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Measure: Sendable {
    public let openingBar: BarLine?              // bar before first event (e.g. anacrusis end)
    public let events: [Event]                   // notes, rests, chords, grace groups, ties, …
    public let closingBar: BarLine               // bar at end; may carry repeat info
    public let endingNumber: [Int]?              // |1, |2, [1,2 variant endings
    public let source: SourceRange
    /// Non-nil when an inline `[M:…]` field changed the meter before this measure.
    /// A renderer should draw the corresponding time-signature glyph before the first note.
    public let meter: Meter?

    public init(
        openingBar: BarLine?,
        events: [Event],
        closingBar: BarLine,
        endingNumber: [Int]?,
        source: SourceRange,
        meter: Meter? = nil
    ) {
        self.openingBar = openingBar
        self.events = events
        self.closingBar = closingBar
        self.endingNumber = endingNumber
        self.source = source
        self.meter = meter
    }
}
