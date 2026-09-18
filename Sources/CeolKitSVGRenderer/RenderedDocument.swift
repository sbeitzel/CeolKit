//
//  RenderedDocument.swift
//  CeolKitSVGRenderer
//
//  What `render(_:)` works out and used to throw away — issue #152.
//

/// Where one tune ended up once the document was packed.
///
/// A multi-tune score shares a page between tunes whenever they fit, so the page a tune
/// starts on is decided by the layout walk and is visible nowhere in the emitted SVG.  A
/// consumer assembling a binder needs it twice over: to print a table of contents, and to
/// answer "turn to page N".
public struct TunePlacement: Sendable, Equatable {
    /// Index into `score.tunes`.
    public let tuneIndex: Int
    /// 0-based index into ``RenderedDocument/pages``.
    public let pageIndex: Int
    /// What that page prints as, after `%%newpage N` and `%%ceolkit:pagenumber`.
    ///
    /// Not the same as `pageIndex + 1`: both directives renumber.
    public let printedPageNumber: Int
    /// The y, in page coordinates, of the top of the tune's title block — or of its first
    /// system where it prints no title.  A tune that starts a page sits at the top margin;
    /// one packed in below another does not.
    public let topY: Double

    public init(tuneIndex: Int, pageIndex: Int, printedPageNumber: Int, topY: Double) {
        self.tuneIndex = tuneIndex
        self.pageIndex = pageIndex
        self.printedPageNumber = printedPageNumber
        self.topY = topY
    }
}

/// A rendered score, together with the layout it was drawn from and where each tune landed.
///
/// ``SVGRenderer/render(_:)`` returns the pages alone, which is all most callers want.
/// ``SVGRenderer/renderDocument(_:)`` returns this instead, for the caller that has to say
/// something about *where* the music went.
public struct RenderedDocument: Sendable {
    /// One SVG string per page — exactly what ``SVGRenderer/render(_:)`` returns.
    public let pages: [String]
    /// The positioned layout the pages were emitted from, footers included.
    public let layout: ResolvedLayout
    /// One entry per tune, in score order.
    ///
    /// `pageIndex` is clamped to the last page there is, so a score that renders no pages
    /// at all leaves every entry pointing at an index `pages` does not have.
    public let placements: [TunePlacement]

    public init(pages: [String], layout: ResolvedLayout, placements: [TunePlacement]) {
        self.pages = pages
        self.layout = layout
        self.placements = placements
    }
}
