/// The `W:` words printed as a block below a tune (ABC v2.2 §5, §6.1.3; issue #187).
///
/// One row per `W:` line, left-aligned at the margin, in source order.  The block is laid out
/// by ``VerticalLayoutEngine`` line by line after the tune's last system, so it breaks across
/// pages like any other content; its rows travel on the page with the title rows, which are
/// drawn the same way.
///
/// Sizes follow `%%wordsfont`, which is scaled with the page like every other text (#203).
enum WordsBlock {
    /// Text size of a line of words, in points, at the default page scale.
    static let fontSize = 12.0

    /// Distance from one line's top to the next's.
    static let lineHeight = fontSize * 1.25

    /// Space between the tune's last system and the first line of words.
    static let topGap = fontSize

    /// Where a line's baseline falls below the top of its line.
    static let baselineOffset = fontSize * LibertinusSerifMetrics.ascenderRatio

    /// The height `lines` lines of words add below a tune, `0` for none.
    static func height(lines: Int) -> Double {
        lines == 0 ? 0 : topGap + Double(lines) * lineHeight
    }

    // MARK: - In a `%%wordsfont` (issue #186)

    /// The same measures for words set in `style`: they scale with its size.
    static func lineHeight(_ style: TextStyle) -> Double { style.size * 1.25 }
    static func topGap(_ style: TextStyle) -> Double { style.size }
    static func height(lines: Int, style: TextStyle) -> Double {
        lines == 0 ? 0 : topGap(style) + Double(lines) * lineHeight(style)
    }
}
