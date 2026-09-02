/// The column of space to the left of a system's staves that its voice labels stand in,
/// and where their right edge falls (ABC v2.2 §4.1: `V:` `name=` and `sname=`).
///
/// Written as one calculation for the same reason ``BracketColumns`` is: the width reserved
/// here is subtracted from the music twice over — the line breaker packs into what is left
/// and the justifier stretches into it — while the layout engine spends it by moving the
/// staves right and the emitter draws into what that vacates.  Everything the four of them
/// need to agree about is stated here once.
///
/// The gutter stands *outside* the bracket columns, so a system with both draws its labels,
/// then its braces and brackets, then its staves.  Anything else would print the label over
/// the furniture.
///
/// A system whose voices carry no label reserves nothing and shifts nothing, which is what
/// keeps every existing single-voice page byte-identical.
struct VoiceLabelGutter: Sendable {

    /// Space between the widest label and whatever stands to its right — the outermost
    /// bracket column, or the staff itself — in staff spaces.
    private static let clearance = 1.0

    /// Label size as a multiple of the staff space.
    ///
    /// abcm2ps sets its `%%voicefont` at 13pt against a 24pt staff; this is the same
    /// proportion rounded to something a reader of the code can hold onto.  A
    /// `%%voicefont`-style directive can override it later without moving anything else.
    private static let fontSizeRatio = 2.0

    /// Advance assumed per character when the text face could not be read.  Only ever
    /// reached on a broken resource, and both the reservation and the drawing take the
    /// same path, so the labels still land in the space kept for them.
    private static let fallbackAdvanceRatio = 0.5

    /// Total space reserved left of everything else.  Zero when no voice has a label.
    let width: Double

    private let staffSize: Double

    /// - Parameters:
    ///   - labels: one entry per staff of the system, top to bottom; `nil` where that
    ///     staff's voice prints no label on this system.
    ///   - font: the text face, or `nil` where it could not be read.
    init(labels: [String?], font: OpenTypeFont?, staffSize: Double) {
        self.staffSize = staffSize
        let widest = labels.compactMap { $0 }.filter { !$0.isEmpty }.reduce(0.0) { widest, label in
            max(widest, Self.width(of: label, font: font, staffSize: staffSize))
        }
        width = widest > 0 ? widest + Self.clearance * staffSize : 0
    }

    /// Absolute x the labels are right-aligned against, given the x the gutter starts at.
    ///
    /// The clearance is the gutter's right-hand part, so the labels end short of it and
    /// nothing they are drawn against has to know how wide they were.
    func rightEdgeX(from leftX: Double) -> Double {
        leftX + width - Self.clearance * staffSize
    }

    /// The size labels are set at, at the given staff size.
    static func fontSize(staffSize: Double) -> Double { fontSizeRatio * staffSize }

    /// How far below the top staff line a label's baseline sits, so that the label is
    /// optically centred on the staff: the staff's own middle, plus half a cap height to
    /// bring the letterforms' centre onto it rather than their baseline.
    static func baselineOffset(staffSize: Double) -> Double {
        2 * staffSize + fontSize(staffSize: staffSize) * LibertinusSerifMetrics.capHeightRatio / 2
    }

    private static func width(of label: String, font: OpenTypeFont?, staffSize: Double) -> Double {
        let size = fontSize(staffSize: staffSize)
        guard let font else { return Double(label.count) * size * fallbackAdvanceRatio }
        return font.width(of: label, fontSize: size)
    }
}
