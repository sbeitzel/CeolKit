//
//  EventSource.swift
//  CeolKit
//
//  Source-position helpers shared by the semantic pass: where an event sits in
//  the ABC text, and how a measure's extent is derived from the events it holds.
//

import Foundation
import CeolKitModel

/// The position an event occupies in the source, when it has one.
///
/// `.directiveAnchor` and `.tempoChange` are positionless: they are effects of a
/// field elsewhere in the line, not text of their own.
func eventSourceRange(_ event: Event) -> SourceRange? {
    switch event {
    case .note(let n): return n.source
    case .rest(let r): return r.source
    case .chord(let c): return c.source
    case .grace(let g): return g.source
    case .tuplet(let t): return t.source
    case .spacer(let s): return s.source
    case .directiveAnchor: return nil
    case .tempoChange: return nil
    }
}

/// True for the zero-width spacers the semantic pass emits at every whitespace
/// run to break beam groups.
func isSpacerEvent(_ event: Event) -> Bool {
    if case .spacer = event { return true }
    return false
}

/// A range starting at `start` and reaching the end of `end`.
///
/// Line and column stay those of `start`, so a measure reports the line its
/// music begins on even when it runs past a line break.
func sourceSpan(from start: SourceRange, through end: SourceRange) -> SourceRange {
    let endOffset = max(start.byteOffset + start.length, end.byteOffset + end.length)
    return SourceRange(
        file: start.file ?? end.file,
        byteOffset: start.byteOffset,
        length: endOffset - start.byteOffset,
        line: start.line,
        column: start.column
    )
}

/// The extent a `Measure` should report: from its first event that occupies
/// source text through the end of its closing barline.
///
/// Leading spacers are skipped — idiomatic ABC puts a space right after every
/// barline, and a beam break is not where the measure starts. The opening
/// barline is likewise not the start: it commonly sits at the end of the
/// *previous* source line, which would misreport the measure's line. It is used
/// only when the measure has no positioned events at all (e.g. a bar carrying
/// nothing but a variant-ending number).
func measureSourceSpan(
    events: [Event],
    openingBar: BarLine?,
    closingBar: BarLine,
    fallback: SourceRange
) -> SourceRange {
    let start = events.lazy
        .filter { !isSpacerEvent($0) }
        .compactMap(eventSourceRange)
        .first
        ?? events.lazy.compactMap(eventSourceRange).first
        ?? openingBar?.source
        ?? fallback
    return sourceSpan(from: start, through: closingBar.source)
}
