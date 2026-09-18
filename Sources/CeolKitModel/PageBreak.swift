//
//  PageBreak.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 9/3/26.
//

import Foundation

/// A `%%newpage` and the point in the tune it breaks before (ABC v2.2 §11.4.7, issue #140).
///
/// `%%newpage` is one of the two directives whose *position* is part of what it means — the
/// other is `%%score` (see ``StaffPlanChange``).  Every other directive CeolKit implements
/// flattens to a last-wins scalar for the whole tune; this one says "the music from here on
/// starts a fresh page", which is a statement about a place.
///
/// The unit is the **stave** — one source line of music, the same unit ``Voice/staves`` is
/// indexed in — because a page break is a system break, and the staves of a system are laid
/// out together.  A break written part-way through a stave is snapped back to the start of
/// the stave enclosing it, with a ``DiagnosticCode/pageBreakSnappedToStave`` diagnostic
/// saying so, on the same reasoning as a staff plan: the music after the directive is what
/// the author wanted moved, and moving the whole stave moves all of it.
public struct PageBreak: Hashable, Sendable {
    /// Index of the stave this break falls *before*, counted from zero at the start of the
    /// tune body.  A break written before any of the tune's music — in the file preamble
    /// ahead of it, or in its header — is 0, and one written after all of it is the tune's
    /// stave count, which puts the break between this tune and the next.
    public let beforeStave: Int

    /// The number the new page prints, from `%%newpage N`, or `nil` for a plain `%%newpage`
    /// that leaves the count alone.  Numbering carries on from here, so the page after a
    /// `%%newpage 20` is 21.
    public let restartingAt: Int?

    /// The orientation the new page takes, from a `%%landscape` written at this break, or
    /// `nil` to keep whatever the page before it had (issue #158).
    ///
    /// A page size is a property of a *page*, and a page cannot change size part-way down,
    /// so a break is the only place a change of orientation can be expressed.  A `%%landscape`
    /// is therefore paired with the `%%newpage` written at the same point — the same gap
    /// between tunes, the same tune header, or the same stave — and one written anywhere else
    /// is dropped with a ``DiagnosticCode/landscapeWithoutPageBreak`` diagnostic rather than
    /// reaching forward to a break the author did not ask for.
    ///
    /// A `%%landscape` in the *file header*, ahead of every tune, is not a change at all: it
    /// is the orientation the document opens in, and stays in ``Tune/directives`` at
    /// ``Scope/fileGlobal`` where it always was.
    public let landscape: Bool?

    /// Where the directive was written, which is not where it takes effect once it snaps.
    public let source: SourceRange

    public init(beforeStave: Int, restartingAt: Int?, landscape: Bool? = nil,
                source: SourceRange) {
        self.beforeStave = beforeStave
        self.restartingAt = restartingAt
        self.landscape = landscape
        self.source = source
    }
}
