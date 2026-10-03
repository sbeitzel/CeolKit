/// The strip at the foot of a page that a `%%footer` is printed in (issue #192).
///
/// Shared by the renderer, which draws the footer there, and the layout engine, which keeps
/// music out of it: footers are stamped onto pages only after they have been laid out, so
/// the two have to agree on where the strip is without either asking the other.
enum FooterBand {
    /// The footer's text size, in points.  Absolute: `%%ceolkit:scale` sizes the music, not
    /// the page furniture.
    static let fontSize = 12.0

    /// Space kept clear between the lowest thing laid out on a page and the top of the
    /// footer's ascenders.
    static let gap = 6.0

    /// The footer's baseline on a page of height `pageHeight`.  Raised by the descender depth
    /// so the bottom of descenders (p, g, y, …) lands on the bottom margin, not below it.
    static func baselineY(pageHeight: Double, bottomMargin: Double) -> Double {
        pageHeight - bottomMargin - fontSize * LibertinusSerifMetrics.descenderRatio
    }

    /// How far above the bottom margin the layout must stop on a page that carries a footer:
    /// the footer's full ascent and descent, plus ``gap``.
    static var reservedHeight: Double {
        fontSize * (LibertinusSerifMetrics.ascenderRatio + LibertinusSerifMetrics.descenderRatio)
            + gap
    }
}
