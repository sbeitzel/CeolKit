import CeolKitModel

/// The text a note carries in double quotes — chord symbols (`"Am7"`, ABC v2.2 §4.18) and
/// annotations (`"^text"`, `"_text"`, `"<text"`, `">text"`, `"@x,y text"`, §4.19) — and the
/// bands above and below the staff that the first two placements stand in.
///
/// Written as one calculation for the same reason ``LyricBand`` is: the space is reserved in
/// one pass and drawn into in another.  ``VerticalLayoutEngine`` counts the lines each staff
/// needs and adds ``height(lines:staffSize:)`` to its `extraAbove` and `extraBelow`; the
/// emitter finds each baseline again from the same offsets.
///
/// Only `^` and `_` annotations and chord symbols take a line of a band.  `<` and `>` stand
/// beside the notehead and `@` wherever it says, and none of the three reserves space.
enum AnnotationBand {

    // MARK: - Metrics

    /// Text size as a multiple of the staff space: abcm2ps sets both `%%gchordfont` and
    /// `%%annotationfont` at 12 points against its 6-point staff space.
    static let fontSizeRatio = 2.0

    /// Distance between one line's baseline and the next, as a multiple of the text size —
    /// the same spacing ``LyricBand`` gives its verses.
    static let lineHeightRatio = 1.2

    /// Air between the band and whatever the staff reaches out to on that side.
    static let padRatio = 0.5

    /// What the staff is taken to reach beyond its outer line wherever a band is drawn, on
    /// top of its ledger lines: the stem of a note written just outside the middle line, and
    /// the fermata that stands a space off the staff.
    static let floorRatio = 1.0

    /// Gap between a `<` or `>` annotation and the notehead it stands beside.
    static let sideGapRatio = 0.4

    /// Gap between an ending bracket's number and an annotation raised into its band.
    static let bracketGapRatio = 0.5

    static func fontSize(staffSize: Double) -> Double { fontSizeRatio * staffSize }

    static func lineHeight(staffSize: Double) -> Double {
        lineHeightRatio * fontSize(staffSize: staffSize)
    }

    /// Space `lines` lines of text need beyond the staff's floor on one side.
    static func height(lines: Int, staffSize: Double) -> Double {
        guard lines > 0 else { return 0 }
        return padRatio * staffSize + Double(lines) * lineHeight(staffSize: staffSize)
    }

    /// Baseline of line `line` above the staff, 0 being the one nearest it, measured *up*
    /// from the floor.  The nearest line sits a descender clear of the pad, so a `g` or a `y`
    /// does not reach down into the staff.
    static func aboveBaselineOffset(line: Int, staffSize: Double) -> Double {
        padRatio * staffSize
            + fontSize(staffSize: staffSize) * LibertinusSerifMetrics.descenderRatio
            + Double(line) * lineHeight(staffSize: staffSize)
    }

    /// Baseline of line `line` below the staff, 0 being the one nearest it, measured *down*
    /// from the floor.
    static func belowBaselineOffset(line: Int, staffSize: Double) -> Double {
        padRatio * staffSize
            + fontSize(staffSize: staffSize) * LibertinusSerifMetrics.ascenderRatio
            + Double(line) * lineHeight(staffSize: staffSize)
    }

    /// Same fallback as ``LyricBand/width(of:font:fontSize:)``.
    static func width(of text: String, font: OpenTypeFont?, fontSize: Double) -> Double {
        LyricBand.width(of: text, font: font, fontSize: fontSize)
    }

    // MARK: - What a note carries

    /// The lines a note puts above the staff, top to bottom.
    ///
    /// §4.19 asks for consecutive annotations of one placement to be drawn "on separate
    /// lines, with the first listed at the top".  The chord symbol goes under them, nearest
    /// the staff, so the chord symbols of a system stand on one line whatever the notes
    /// around them are annotated with.
    ///
    /// Unprefixed text that is not a chord (``AnnotationPosition/chordLine``) is printed on
    /// the chord line with the chord symbol, as abcm2ps prints it; where a note has more
    /// than one, they stack in the order written, the first at the top (issue #177).
    static func linesAbove(chordSymbol: ChordSymbol?, annotations: [Annotation]) -> [String] {
        let chordLine = (chordSymbol.map { [($0.source.byteOffset, $0.raw)] } ?? [])
            + annotations.filter { $0.position == .chordLine }.map { ($0.source.byteOffset, $0.text.value) }
        return texts(in: annotations, at: .above)
            + chordLine.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The lines a note puts below the staff, top to bottom — the first listed nearest it.
    static func linesBelow(annotations: [Annotation]) -> [String] {
        texts(in: annotations, at: .below)
    }

    static func texts(in annotations: [Annotation], at position: AnnotationPosition) -> [String] {
        annotations.filter { $0.position == position }.map(\.text.value)
    }

    /// How many lines the events of one staff-system need above and below it: the most any
    /// one note carries, since every note's lines share the band.
    static func lineCounts(of events: some Sequence<Event>) -> (above: Int, below: Int) {
        events.reduce((above: 0, below: 0)) { widest, event in
            let own = lineCounts(of: event)
            return (max(widest.above, own.above), max(widest.below, own.below))
        }
    }

    static func lineCounts(of event: Event) -> (above: Int, below: Int) {
        switch event {
        case .note(let n):
            return (linesAbove(chordSymbol: n.chordSymbol, annotations: n.annotations).count,
                    linesBelow(annotations: n.annotations).count)
        case .chord(let c):
            return (linesAbove(chordSymbol: c.chordSymbol, annotations: c.annotations).count,
                    linesBelow(annotations: c.annotations).count)
        case .tuplet(let t):
            return lineCounts(of: t.events)
        default:
            return (0, 0)
        }
    }
}
