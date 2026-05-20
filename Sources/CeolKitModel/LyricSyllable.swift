//
//  LyricSyllable.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// The lyric alignment attached to a note by the semantic pass from `w:` lines (§6 step 8).
///
/// `Note.lyric == nil` means no `w:` line applies or the line is exhausted (see §10
/// open question 5). `.skip` means a `w:` line exists but explicitly passed over this
/// note with `*` — the two cases are semantically distinct.
public enum LyricSyllable: Hashable {
    /// A syllable with display text. `connection` tells the renderer whether to draw
    /// a hyphen connector to the next aligned note.
    case text(TextString, connection: LyricConnection)

    /// `_` — this note extends the previous syllable; renderer draws an extender line.
    case melisma

    /// `*` — this note is explicitly skipped; no text or extender is drawn.
    case skip
}

public enum LyricConnection: Hashable {
    case wordEnd    // syllable ends a word; no connector
    case hyphen     // mid-word; renderer draws a hyphen to the next syllable
}
