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

    /// Where the directive was written, which is not where it takes effect once it snaps.
    public let source: SourceRange

    public init(beforeStave: Int, restartingAt: Int?, source: SourceRange) {
        self.beforeStave = beforeStave
        self.restartingAt = restartingAt
        self.source = source
    }
}
