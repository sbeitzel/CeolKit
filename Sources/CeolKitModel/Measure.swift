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
    /// The variant endings (`|1`, `:|2`, `[1,2`, `[1-3`) this measure opens, in the order
    /// they were written; empty where it opens none.
    ///
    /// A measure usually opens at most one.  More than one means a bar whose variants differ
    /// only part way through, written `| ab [1 cd [2 ef |`: the music before the first `[N`
    /// is common to every pass, and each ending runs on to the next.
    public let endings: [VariantEnding]
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
    ///
    /// Only a `K:` that names a key sets this.  One that changes the clef alone (`K:bass`,
    /// `[K:clef=bass]`) leaves the signature as it was, and is an `Event.clefChange` in
    /// `events` instead (#223).  The key's `clef` is the clef in force from this measure on.
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
        endings: [VariantEnding] = [],
        source: SourceRange,
        meter: Meter? = nil,
        key: KeySignature? = nil,
        unitNoteLength: Fraction
    ) {
        self.openingBar = openingBar
        self.events = events
        self.closingBar = closingBar
        self.endings = endings
        self.source = source
        self.meter = meter
        self.key = key
        self.unitNoteLength = unitNoteLength
    }
}

/// One variant ending opened in a measure: the passes it is played on, and where in the
/// measure it begins.
public struct VariantEnding: Sendable, Equatable, Hashable {
    /// The passes this ending is played on — `[1]` for `|1`, `[1, 2, 3]` for `[1-3` or
    /// `[1,2,3`.  The semantic pass keeps no record of whether a range was written.
    public let numbers: [Int]
    /// Where in the measure's `events` the ending begins, or `nil` where it begins at the
    /// measure's opening bar line — as `|1`, `:|2`, and a `[1` written against a bar line
    /// all do.
    ///
    /// ABC v2.2 §4.10 ties only the *end* of an ending to a bar line: a bare `[N` may stand
    /// part way through a bar, as a pickup that differs between the first and second time
    /// through is usually written (#172), or as the second half of a bar whose variants
    /// differ only there.  This is then the index of the first event after it, and a
    /// renderer starts the ending's bracket there rather than at the bar line.
    public let startIndex: Int?

    public init(numbers: [Int], startIndex: Int? = nil) {
        self.numbers = numbers
        self.startIndex = startIndex
    }
}
