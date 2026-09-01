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
    /// The text this measure occupies: from its first event that has a position
    /// in the source through the end of `closingBar`.
    ///
    /// `line`/`column` are those of the start, so a measure carried over a line
    /// break reports the line its music begins on. The opening barline is not
    /// included — it commonly sits at the end of the previous source line, and it
    /// is already the `closingBar` of the preceding measure.
    public let source: SourceRange
    /// Non-nil when an inline `[M:…]` field changed the meter before this measure.
    /// A renderer should draw the corresponding time-signature glyph before the first note.
    public let meter: Meter?
    /// Non-nil when an `L:` field changed the unit note length at this measure, after the
    /// voice had already begun. `nil` means "whatever was in force at the previous measure",
    /// which for the first measure of a voice is `Voice.unitNoteLength` — the length the
    /// voice opened in.
    ///
    /// `Event` durations are counted in unit note lengths, so this is what says what those
    /// counts are worth from here on: it is the divisor beaming is decided against, and the
    /// one a renderer needs to size a note head.
    public let unitNoteLength: Fraction?

    public init(
        openingBar: BarLine?,
        events: [Event],
        closingBar: BarLine,
        endingNumber: [Int]?,
        source: SourceRange,
        meter: Meter? = nil,
        unitNoteLength: Fraction? = nil
    ) {
        self.openingBar = openingBar
        self.events = events
        self.closingBar = closingBar
        self.endingNumber = endingNumber
        self.source = source
        self.meter = meter
        self.unitNoteLength = unitNoteLength
    }
}
