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
    /// Non-nil when a `K:` field changed the key before this measure — the same convention
    /// `meter` uses, and for the same reason: a key signature is engraved exactly where the
    /// key moves, so "changed here" is the useful shape.
    ///
    /// It is the *new* key, not the accidentals to draw: what a renderer engraves at the
    /// point of change also depends on the key being left behind, whose accidentals are
    /// cancelled with naturals, and on the clef the staff carries. The key in force before
    /// this measure is the last preceding `key`, with `Voice.key` (failing that `Tune.key`)
    /// standing for a voice that has not changed one yet.
    ///
    /// A `K:` written part way through a bar lands on the bar it falls in, exactly as a
    /// mid-bar `L:` does (#122): a measure carries one signature, so there is nowhere finer
    /// for it to go.
    public let key: KeySignature?
    /// The unit note length this measure's durations are counted in — always the effective
    /// value, on every measure, not only where an `L:` moved it.
    ///
    /// `Event.duration` is a multiple of this, so it is the divisor beaming is decided
    /// against and the one a renderer needs to size a note head, a stem and a flag.
    ///
    /// This deliberately does not follow the convention `meter` uses, where non-nil means
    /// "changed here": a renderer must draw a time signature exactly where the meter changes,
    /// whereas a unit note length is never drawn, only used as a scale. "Always the effective
    /// value" is the useful shape for a divisor; "only where it changed" is the useful shape
    /// for something engraved at the point of change.
    ///
    /// "Did it change here?" is still recoverable as `m.unitNoteLength != previous`, with
    /// `Voice.unitNoteLength` as the comparison for a voice's first measure.
    public let unitNoteLength: Fraction

    public init(
        openingBar: BarLine?,
        events: [Event],
        closingBar: BarLine,
        endingNumber: [Int]?,
        source: SourceRange,
        meter: Meter? = nil,
        key: KeySignature? = nil,
        unitNoteLength: Fraction
    ) {
        self.openingBar = openingBar
        self.events = events
        self.closingBar = closingBar
        self.endingNumber = endingNumber
        self.source = source
        self.meter = meter
        self.key = key
        self.unitNoteLength = unitNoteLength
    }
}
