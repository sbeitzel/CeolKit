import CeolKitModel

/// Widens a sized bar until the text its notes carry — chord symbols and annotations, ABC
/// v2.2 §4.18–4.19 — no longer runs into the text on the notes after it (issue #185).
///
/// The columns ``ColumnMetrics`` sizes are spaced for the music and, where a `w:` line
/// reaches them, for the syllables under it.  Text above and below the staff was never
/// measured, so a chord symbol wider than its note's column printed over the next one.  This
/// pass runs after the columns are laid out, because the constraint is not a property of one
/// column: a chord on a half note followed by three bare eighths has four columns to clear
/// before the next chord, not one.
///
/// What is kept apart:
/// - **Above the staff**, each note's widest line — chord symbol, chord-line text or `^`
///   annotation, measured as drawn, with a chord's accidentals as their signs — against the
///   next note that carries any.  All of a note's lines are left-aligned on it, and the line
///   one note's text lands on depends on how many the note carries, so any of them can meet
///   any of the next note's.
/// - **Below the staff**, the same for `_` annotations.
/// - **Beside the notehead**, `>` text against the next note, and `<` text against the one
///   before, or the bar line where there is none.
///
/// `@` annotations are placed where the author put them, and are left alone.
///
/// The space a pair needs is shared out evenly over the column boundaries between them, so
/// the notes in between stay evenly spaced rather than all of it opening up before the
/// second.  Text on the last note of a bar has to end within the bar, give or take the
/// notehead gap every bar starts with: what the next bar opens with is not known here.
///
/// A bar whose notes carry no text comes back unchanged.
struct AnnotationSpacing: Sendable {
    let metrics: ColumnMetrics

    /// Air left between one note's text and the next's, as a multiple of the staff space.
    /// Wider than the gap ``LyricBand`` leaves between syllables: those read as one line of
    /// words, where two chord symbols side by side have to read as two.
    static let gapRatio = 1.0

    func widen(_ sized: SizedMeasure) -> SizedMeasure {
        let events = sized.measure.events
        guard events.count == sized.eventOffsets.count,
              events.contains(where: Self.carriesText) else { return sized }

        let s = metrics.config.staffSize
        let gap = Self.gapRatio * s
        let nhw = metrics.noteheadWidth()
        var offsets = sized.eventOffsets
        var width = sized.naturalWidth

        // Each column a shift can open up in front of: the first event of every spacing
        // group, a grace event standing in for the note it is paired with.
        let starts: [Int] = events.indices.filter { i in
            guard metrics.isSpacingEvent(events[i]) || events[i].isGrace else { return false }
            return !(i > 0 && sized.graceEventIndices.contains(i - 1))
        }
        /// The spacing event a column start leads to: itself, or the note a grace precedes.
        func note(at start: Int) -> Int {
            sized.graceEventIndices.contains(start) ? start + 1 : start
        }
        let notes = starts.map(note(at:)).filter { metrics.isSpacingEvent(events[$0]) }

        /// Opens `deficit` up between `from` (exclusive) and `to` (inclusive, a position on
        /// the page), spread evenly over the column starts in that span and the bar end where
        /// `to` is the bar end.
        func open(_ deficit: Double, after from: Double, through to: Double?) {
            guard deficit > 0.0001 else { return }
            let boundaries = starts.map { offsets[$0] }.filter { start in
                start > from + 0.0001 && (to.map { start <= $0 + 0.0001 } ?? true)
            }
            let slots = boundaries.count + (to == nil ? 1 : 0)
            guard slots > 0 else { return }
            let share = deficit / Double(slots)
            let original = offsets
            for i in offsets.indices where original[i] > from + 0.0001 {
                let passed = boundaries.filter { $0 <= original[i] + 0.0001 }.count
                offsets[i] += share * Double(passed)
            }
            width += deficit
        }

        // Above and below the staff: each text-bearing note against the next one.
        for band in [Band.above, .below] {
            let bearing = notes.filter { textWidth(of: events[$0], band: band) > 0 }
            for (k, i) in bearing.enumerated() {
                let need = textWidth(of: events[i], band: band) + gap
                if k + 1 < bearing.count {
                    let j = bearing[k + 1]
                    guard offsets[j] > offsets[i] + 0.0001 else { continue }
                    open(need - (offsets[j] - offsets[i]), after: offsets[i],
                         through: offsets[j])
                } else {
                    open(need - (width + nhw - offsets[i]), after: offsets[i], through: nil)
                }
            }
        }

        // Beside the notehead: `>` text must clear the next note, `<` text the one before.
        let sideGap = AnnotationBand.sideGapRatio * s
        for (k, i) in notes.enumerated() {
            let right = sideWidth(of: events[i], position: .right)
            if right > 0 {
                let need = nhw + sideGap + dotAllowance(events[i]) + right + gap
                let end = k + 1 < notes.count ? offsets[notes[k + 1]] : width + nhw
                open(need - (end - offsets[i]), after: offsets[i],
                     through: k + 1 < notes.count ? end : nil)
            }
            let left = sideWidth(of: events[i], position: .left)
            if left > 0 {
                let reach = left + sideGap + accidentalReservation(events[i])
                if k > 0 {
                    let previous = notes[k - 1]
                    open(nhw + gap + reach - (offsets[i] - offsets[previous]),
                         after: offsets[previous], through: offsets[i])
                } else {
                    // The bar's first note: its text has to clear the bar line.
                    open(gap + reach - offsets[i], after: -1, through: offsets[i])
                }
            }
        }

        guard width != sized.naturalWidth else { return sized }
        return SizedMeasure(measure: sized.measure, naturalWidth: width, eventOffsets: offsets,
                            unitNoteLength: sized.unitNoteLength,
                            graceEventIndices: sized.graceEventIndices,
                            eventVoiceIndices: sized.eventVoiceIndices,
                            keyChange: sized.keyChange,
                            musicOffsets: sized.musicOffsets, musicWidth: sized.musicWidth)
    }

    // MARK: - Measuring

    private enum Band { case above, below }

    /// Width of the widest line `event` draws in `band`, `0` where it draws none.
    private func textWidth(of event: Event, band: Band) -> Double {
        guard let (chordSymbol, annotations) = Self.text(of: event) else { return 0 }
        let lines: [(line: AnnotationBand.Line, isChordLine: Bool)] = switch band {
        case .above:
            AnnotationBand.styledLinesAbove(chordSymbol: chordSymbol, annotations: annotations)
        case .below:
            AnnotationBand.linesBelow(annotations: annotations).map { ([.text($0)], false) }
        }
        return lines.map {
            let style = $0.isChordLine ? metrics.styles.chordSymbol : metrics.styles.annotation
            return AnnotationBand.width(of: $0.line, font: style.measuringFont,
                                        metadata: metrics.metadata, fontSize: style.size)
        }.max() ?? 0
    }

    /// Width of the widest `<` or `>` line beside `event`'s notehead.
    private func sideWidth(of event: Event, position: AnnotationPosition) -> Double {
        guard let (_, annotations) = Self.text(of: event) else { return 0 }
        return AnnotationBand.texts(in: annotations, at: position).map {
            metrics.styles.annotation.width(of: $0)
        }.max() ?? 0
    }

    /// The dot the emitter steps `>` text past, as it does when drawing.
    private func dotAllowance(_ event: Event) -> Double {
        let dotted: Bool = switch event {
        case .note(let n):  metrics.isDottedDuration(n.duration)
        case .chord(let c): metrics.isDottedDuration(c.duration)
        default:            false
        }
        return dotted ? metrics.config.staffSize : 0
    }

    /// The accidental `<` text is set to the left of, as the emitter sets it.
    private func accidentalReservation(_ event: Event) -> Double {
        let notes: [Note] = switch event {
        case .note(let n):  [n]
        case .chord(let c): c.notes
        default:            []
        }
        return notes.map { metrics.accidentalMetrics.reservation(for: $0.displayedAccidental) }
            .max() ?? 0
    }

    private static func text(of event: Event)
        -> (chordSymbol: ChordSymbol?, annotations: [Annotation])? {
        switch event {
        case .note(let n):  return (n.chordSymbol, n.annotations)
        case .chord(let c): return (c.chordSymbol, c.annotations)
        default:            return nil
        }
    }

    private static func carriesText(_ event: Event) -> Bool {
        guard let (chordSymbol, annotations) = text(of: event) else { return false }
        return chordSymbol != nil || !annotations.isEmpty
    }
}

private extension Event {
    var isGrace: Bool {
        if case .grace = self { return true }
        return false
    }
}
