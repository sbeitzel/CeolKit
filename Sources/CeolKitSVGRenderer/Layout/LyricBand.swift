import CeolKitModel

/// The band of verses printed below a staff, and where each of them sits in it
/// (ABC v2.2 §4.18: `w:`).
///
/// Written as one calculation for the same reason ``VoiceLabelGutter`` is: the space is
/// reserved in one pass and drawn into in another.  ``VerticalLayoutEngine`` adds
/// ``height(verses:staffSize:)`` to the staff's `extraBelow`, and the emitter takes the band
/// back off the bottom of the system to find the baselines — so everything the two of them
/// have to agree about is stated here once, including how many verses a system carries.
///
/// A staff whose notes carry no syllable reserves nothing and draws nothing, which is what
/// keeps every page of every tune without lyrics exactly as it was.
enum LyricBand {

    /// Syllable size as a multiple of the staff space.  Twelve points against a 24-point
    /// staff, which is what abcm2ps sets `%%vocalfont` at.
    static let fontSizeRatio = 2.0

    /// Distance between one verse's baseline and the next, as a multiple of the syllable
    /// size.  Enough to clear a descender in the verse above and leave a little air.
    static let lineHeightRatio = 1.2

    static func fontSize(staffSize: Double) -> Double { fontSizeRatio * staffSize }

    static func lineHeight(staffSize: Double) -> Double {
        lineHeightRatio * fontSize(staffSize: staffSize)
    }

    /// Space `verses` verses need below everything else the staff reaches down to.
    static func height(verses: Int, staffSize: Double) -> Double {
        guard verses > 0 else { return 0 }
        return Double(verses) * lineHeight(staffSize: staffSize)
    }

    /// Baseline of verse `verse` (0-based), measured down from the top of the band.
    ///
    /// The syllables hang from the top of their line rather than sitting on its foot, so
    /// the gap between two verses is the one `lineHeightRatio` describes whatever the
    /// deepest descender in the verse above turns out to be.
    static func baselineOffset(verse: Int, staffSize: Double) -> Double {
        Double(verse) * lineHeight(staffSize: staffSize)
            + fontSize(staffSize: staffSize) * LibertinusSerifMetrics.ascenderRatio
    }

    /// Thickness of a melisma's extender line.
    static func extenderThickness(staffSize: Double) -> Double { staffSize * 0.12 }

    // MARK: - Horizontal room

    /// Space that must separate one syllable from the next, as a multiple of the staff space.
    static let syllableGapRatio = 0.6

    /// How wide the column under a note has to be for the syllables it carries.
    ///
    /// A syllable is centred on its notehead, so it reaches half its width into the column
    /// on either side: the column between two sung notes has to hold half of each syllable
    /// and a gap between them.  ``ColumnMetrics`` widens the column to this where the music
    /// alone would have spaced the notes closer, which is what stops a sung line from
    /// printing on top of itself.
    ///
    /// - Parameters:
    ///   - own: width of the widest syllable under the note this column belongs to.
    ///   - next: the same for the note the column runs to, `0` where nothing is sung there
    ///     or the column is the last of its bar.
    ///   - hyphenated: whether a verse divides a word here, so the gap has to hold the
    ///     hyphen that joins the two halves as well as separating them.
    ///
    /// Zero where neither note is sung, so a tune without lyrics is spaced exactly as it was
    /// before they were drawn.
    static func columnReservation(own: Double, next: Double, hyphenated: Bool,
                                  staffSize: Double, font: OpenTypeFont?) -> Double {
        guard own > 0 || next > 0 else { return 0 }
        var gap = syllableGapRatio * staffSize
        if hyphenated {
            gap += width(of: "-", font: font, fontSize: fontSize(staffSize: staffSize))
        }
        return (own + next) / 2 + gap
    }

    /// Whether any verse divides a word at this note — a syllable written with a trailing
    /// `-`, whose hyphen is drawn in the gap that follows it.
    static func isHyphenated(_ lyrics: [LyricSyllable?]) -> Bool {
        lyrics.contains { if case .text(_, .hyphen) = $0 { return true }; return false }
    }

    /// Width of the widest syllable a note's verses put under it, `0` for a note no verse
    /// reaches or that only holds a melisma.
    static func widestSyllable(in lyrics: [LyricSyllable?], staffSize: Double,
                               font: OpenTypeFont?) -> Double {
        lyrics.reduce(0.0) { widest, syllable in
            guard case .text(let text, _) = syllable else { return widest }
            return max(widest, width(of: displayText(text.value), font: font,
                                     fontSize: fontSize(staffSize: staffSize)))
        }
    }

    /// What a syllable prints: `~` links two words onto one note (§4.18) and is set as the
    /// space it stands for.
    static func displayText(_ text: String) -> String {
        text.replacing("~", with: " ")
    }

    /// Same fallback as ``VoiceLabelGutter``: a text resource that could not be read costs
    /// the syllables their exact placement, not the page.  Measuring and drawing take this
    /// path together, so they still agree.
    static func width(of text: String, font: OpenTypeFont?, fontSize: Double) -> Double {
        guard let font else { return Double(text.count) * fontSize * 0.5 }
        return font.width(of: text, fontSize: fontSize)
    }

    // MARK: - Verse counting

    /// How many verses the events of one staff-system carry — the number of `w:` lines that
    /// reached any of its notes, which is what decides how deep the band is.
    static func verseCount(of events: some Sequence<Event>) -> Int {
        events.reduce(0) { max($0, verseCount(of: $1)) }
    }

    static func verseCount(of event: Event) -> Int {
        switch event {
        case .note(let n):   return n.lyrics.count
        case .chord(let c):  return c.lyrics.count
        case .tuplet(let t): return verseCount(of: t.events)
        default:             return 0
        }
    }

    /// The same count taken from a laid-out staff, so the emitter and the layout engine
    /// arrive at the same band from the two forms the events reach them in.
    static func verseCount(of system: ResolvedSystem) -> Int {
        system.measures.reduce(0) { widest, measure in
            measure.events.reduce(widest) { max($0, verseCount(of: $1.kind)) }
        }
    }

    static func verseCount(of kind: ResolvedEventKind) -> Int {
        switch kind {
        case .note(let n):   return n.lyrics.count
        case .chord(let c):  return c.lyrics.count
        case .tuplet(let t): return verseCount(of: t.events)
        default:             return 0
        }
    }
}
