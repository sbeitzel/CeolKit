import Foundation
import CeolKitModel

/// Pass 1¾: merges the voices of a `( … )` group (ABC v2.2 §11.1) into the single event
/// sequence one staff is drawn from, keyed by **onset**.
///
/// Everything downstream of here places events by their index in a flat array — the sizer
/// accumulates `x` per event, and `SizedMeasure.eventOffsets` is index-parallel to
/// `Measure.events`.  Duration sizes a column but never *places* one, so two voices agree
/// only at bar lines.  That is tolerable on two staves and impossible on one, where a note
/// in the lower voice has to sit under the note the upper voice sounds with it.
///
/// So the merge runs *before* sizing rather than after grouping.  `LineBreaker` and
/// `Justifier` both take a column's width as the max across staves, which is right for two
/// staves and wrong for one: interleaved onsets need *more* columns than either voice alone,
/// and no `max` can invent them.
///
/// ## What a column is here
///
/// One onset, subdivided.  Every voice sounding at an onset contributes a run of events —
/// any grace groups, spacers, directive anchors and tempo changes that precede the note,
/// then the note itself — and those runs are **right-aligned** against the onset, so the
/// principal notes of every voice land in the same sub-column at the same x while their
/// approach spacing stays their own.  A sub-column is as wide as the widest thing any voice
/// puts in it.
///
/// The principal sub-column is spaced for the distance to the *next* onset rather than for
/// the notes' own durations: a half note in one voice against four eighths in another gets
/// the four eighth-columns it sounds across, not a half note's worth of space followed by
/// three crushed ones.  Where the voices agree on every onset — two identical voices, or one
/// voice merged with nothing — inter-onset distance *is* the note's duration, and the result
/// is offset-for-offset what ``MeasureSizer`` alone produces.
///
/// ## Two traps, both load-bearing
///
/// **Padded measures are dropped, not merged.**  ``VoiceAligner`` fills a short voice with
/// an invisible full-measure rest, and a rest sizes to at least the minimum column — so a
/// padded bar would widen the shared staff for music nobody wrote.  ``VoicePart/isPadding``
/// is the aligner's own answer to that, not a guess made from the events.
///
/// **Grace groups keep their principal note adjacent.**  `Justifier.stretchOffsets` reads
/// `graceEventIndices` as indices into the flat offsets array and pairs *i* with *i+1*, so
/// a merge that interleaved a grace away from its note would corrupt grace spacing silently.
/// Events are therefore emitted voice by voice within an onset — never sub-column by
/// sub-column — which keeps every run contiguous and every grace pair adjacent.
struct SharedStaffMerger: Sendable {

    /// One voice's contribution to one bar of a shared staff.
    struct VoicePart {
        let measure: Measure
        /// The voice's own `L:`, which its co-tenants need not share (§7.3).
        let unitNoteLength: Fraction
        /// The voice's position within the staff, top to bottom.  This is what
        /// ``SizedMeasure/eventVoiceIndices`` carries.
        let voiceIndex: Int
        /// `true` when ``VoiceAligner`` invented this measure to keep the staves the same
        /// length.  Such a measure contributes no columns.
        let isPadding: Bool
    }

    private let metrics: ColumnMetrics

    init(metrics: ColumnMetrics) {
        self.metrics = metrics
    }

    // MARK: - Merge

    /// Merges `parts` — the voices of one shared staff, for one bar — into a single sized
    /// measure.
    ///
    /// Callers with fewer than two sounding voices should size with ``MeasureSizer`` instead;
    /// this handles the case anyway, and identically, but the sizer says what it means.
    func merge(_ parts: [VoicePart]) -> SizedMeasure {
        let sounding = parts.filter { !$0.isPadding }
        // Every voice padded: the bar is furniture only.  Its bar lines still draw, so it
        // keeps its width, and it contributes not one column of music.
        guard let primary = sounding.first ?? parts.first else {
            return SizedMeasure(measure: emptyMeasure(), naturalWidth: 0, eventOffsets: [])
        }
        let voices = sounding.map { Prepared(part: $0, metrics: metrics) }

        // The bar's clock runs as far as its longest voice.  The last column is spaced for
        // the distance from its onset to there.
        let end = voices.map(\.end).max() ?? .zero
        let onsets = Set(voices.flatMap { $0.slots.map(\.onset) }).sorted()

        var mergedEvents: [Event] = []
        var offsets: [Double] = []
        var voiceTags: [Int] = []
        var graceEventIndices: Set<Int> = []

        var x = voices.map { metrics.leftMargin(for: $0.part.measure) }.max()
            ?? metrics.leftMargin(for: primary.measure)

        for (index, onset) in onsets.enumerated() {
            let next = index + 1 < onsets.count ? onsets[index + 1] : end
            let gapQuarters = (next - onset).value

            // Sub-columns: as many as the busiest voice needs at this onset, each as wide as
            // the widest thing any voice puts in it.  A voice with fewer events right-aligns
            // into the last of them, so the principal notes coincide.
            let runs = voices.compactMap { voice -> Run? in
                voice.slot(at: onset).map { Run(voice: voice, slot: $0, gapQuarters: gapQuarters,
                                                metrics: metrics) }
            }
            let subColumnCount = runs.map(\.widths.count).max() ?? 0
            var subWidths = [Double](repeating: 0, count: subColumnCount)
            for run in runs {
                for (j, width) in run.widths.enumerated() {
                    let sub = subColumnCount - run.widths.count + j
                    subWidths[sub] = max(subWidths[sub], width)
                }
            }
            // A column whose voices collide has a head displaced sideways out of it (#79),
            // and a head displaced by its own width into a column sized for one is drawn over
            // whatever stands next to it.  Room to the right goes into the principal
            // sub-column — the last, the one every voice's note lands in; room to the left is
            // opened by starting the whole column further along.
            let extra = NoteheadCollisions.extraWidth(runs.flatMap(\.collisionHeads),
                                                      noteheadWidth: metrics.noteheadWidth())
            if subColumnCount > 0 { subWidths[subColumnCount - 1] += extra.right }

            var subX = [Double](repeating: 0, count: subColumnCount)
            var cursor = x + extra.left
            for j in 0..<subColumnCount {
                subX[j] = cursor
                cursor += subWidths[j]
            }

            // Emitted voice by voice, so each voice's run stays contiguous and every grace
            // group keeps the note it belongs to immediately after it.
            for run in runs {
                let first = subColumnCount - run.widths.count
                for (j, eventIndex) in run.slot.events.enumerated() {
                    if run.pairedGraceOffsets.contains(j) {
                        graceEventIndices.insert(offsets.count)
                    }
                    mergedEvents.append(run.voice.part.measure.events[eventIndex])
                    offsets.append(subX[first + j])
                    voiceTags.append(run.voice.part.voiceIndex)
                }
            }
            x = cursor
        }

        let naturalWidth = x + (voices.map { metrics.rightPadding(for: $0.part.measure) }.max()
            ?? metrics.rightPadding(for: primary.measure))

        return SizedMeasure(
            measure: Measure(openingBar: primary.measure.openingBar, events: mergedEvents,
                             closingBar: primary.measure.closingBar,
                             endingNumber: primary.measure.endingNumber,
                             source: primary.measure.source, meter: primary.measure.meter),
            naturalWidth: naturalWidth,
            eventOffsets: offsets,
            unitNoteLength: primary.unitNoteLength,
            graceEventIndices: graceEventIndices,
            eventVoiceIndices: voiceTags)
    }

    /// The measure a fully padded bar keeps: its own furniture, and no music at all.
    private func emptyMeasure() -> Measure {
        let bar = BarLine(kind: .single, source: .emptySourceRange)
        return Measure(openingBar: nil, events: [], closingBar: bar, endingNumber: nil,
                       source: .emptySourceRange)
    }

    // MARK: - One voice, cut into onsets

    /// A voice's bar as a list of onsets, each holding the run of events that sounds there.
    private struct Prepared {
        let part: VoicePart
        /// Quarter notes per unit note length, for this voice's `L:`.
        let quarterInUnits: Double
        let slots: [Slot]
        /// Where this voice's music ends, as an onset.
        let end: Rational

        struct Slot {
            let onset: Rational
            /// Indices into the measure's events, in source order.  The last is the note,
            /// chord, rest or tuplet that sounds at ``onset`` — unless the run is the tail of
            /// a bar that ends with grace notes or a directive, which sounds nothing.
            let events: [Int]
        }

        init(part: VoicePart, metrics: ColumnMetrics) {
            self.part = part
            let unl = Double(part.unitNoteLength.numerator) / Double(part.unitNoteLength.denominator)
            self.quarterInUnits = 0.25 / unl

            var slots: [Slot] = []
            var pending: [Int] = []
            var onset = Rational.zero
            for (index, event) in part.measure.events.enumerated() {
                let duration = Rational.quarters(of: event, unitNoteLength: part.unitNoteLength)
                guard duration > .zero else {
                    // Grace groups, spacers, directive anchors, tempo changes: they take
                    // width but no time, so they belong to the onset they lead up to.
                    pending.append(index)
                    continue
                }
                slots.append(Slot(onset: onset, events: pending + [index]))
                pending = []
                onset = onset + duration
            }
            // A bar that ends with something untimed still has to draw it.
            if !pending.isEmpty { slots.append(Slot(onset: onset, events: pending)) }

            self.slots = slots
            self.end = onset
        }

        func slot(at onset: Rational) -> Slot? {
            slots.first { $0.onset == onset }
        }
    }

    /// One voice's events at one onset, with the width each of them claims.
    private struct Run {
        let voice: Prepared
        let slot: Prepared.Slot
        let widths: [Double]
        /// The noteheads this voice draws at the onset — what ``NoteheadCollisions`` needs to
        /// say whether the column has to be widened for a displaced head.
        let collisionHeads: [CollisionHead]
        /// Positions within ``slot`` holding a grace group that is immediately followed by
        /// the note it ornaments — the pairs `Justifier.stretchOffsets` must not stretch.
        let pairedGraceOffsets: Set<Int>

        init(voice: Prepared, slot: Prepared.Slot, gapQuarters: Double, metrics: ColumnMetrics) {
            self.voice = voice
            self.slot = slot

            let events = slot.events.map { voice.part.measure.events[$0] }
            var widths: [Double] = []
            var paired: Set<Int> = []
            for (j, event) in events.enumerated() {
                // A grace group and the note it ornaments move together: the group's width
                // plus the gap to the notehead is one fixed sub-column.
                if case .grace(let group) = event, j + 1 < events.count,
                   metrics.isSpacingEvent(events[j + 1]) {
                    paired.insert(j)
                    widths.append(metrics.graceGroupWidth(group) + metrics.graceNoteGap(for: group))
                    continue
                }
                // The last event of a run is the one that sounds, and it is spaced for the
                // distance to the next onset rather than for its own duration — on a shared
                // staff those differ whenever the voices do.
                let sounds = j == events.count - 1 && metrics.soundingDuration(event) > 0
                widths.append(metrics.columnWidth(
                    for: event,
                    durationUnits: sounds ? gapQuarters * voice.quarterInUnits : nil,
                    quarterInUnits: voice.quarterInUnits))
            }
            self.widths = widths
            self.pairedGraceOffsets = paired
            // Only the event that sounds draws a head at this onset; a grace group ahead of
            // it is drawn clear of the column and never collides with the other voice.
            self.collisionHeads = events.last.map {
                Run.heads(of: $0, voice: voice, metrics: metrics)
            } ?? []
        }

        /// The heads `event` draws, as the collision pass sees them.
        ///
        /// The stem direction given is the opposition a shared staff imposes (#77), which is
        /// right for all but a voice that stated `V:` `stem=` — and wrong there only about
        /// *which way* a unison separates, never about whether it separates at all, which is
        /// the whole of what the sizer is asking.
        private static func heads(of event: Event, voice: Prepared,
                                  metrics: ColumnMetrics) -> [CollisionHead] {
            let unl = voice.part.unitNoteLength
            func head(_ note: Note) -> CollisionHead {
                let duration = Double(note.duration.numerator) / Double(note.duration.denominator)
                    * Double(unl.numerator) / Double(unl.denominator)
                return CollisionHead(
                    voiceIndex: voice.part.voiceIndex,
                    staffPos: CollisionHead.staffPosition(of: note.pitch),
                    glyph: .notehead(absoluteDuration: duration),
                    isDotted: metrics.isDottedDuration(note.duration),
                    accidental: note.displayedAccidental,
                    stemUp: voice.part.voiceIndex == 0)
            }
            switch event {
            case .note(let n):  return [head(n)]
            case .chord(let c): return c.notes.map(head)
            default:            return []
            }
        }
    }
}

// MARK: - Onsets

/// An exact position in time within a bar, in quarter notes.
///
/// Rational rather than `Double` because onsets are *compared*: two voices sound together
/// when their onsets are equal, and a tuplet against plain notes makes thirds of a beat that
/// no binary fraction represents.  One rounding error would split a shared column in two.
struct Rational: Hashable, Comparable {
    let numerator: Int
    /// Always positive; the sign lives in ``numerator``.
    let denominator: Int

    static let zero = Rational(0, 1)

    init(_ numerator: Int, _ denominator: Int) {
        precondition(denominator != 0, "a rational onset cannot have a zero denominator")
        let sign = denominator < 0 ? -1 : 1
        let n = numerator * sign
        let d = denominator * sign
        let g = Rational.gcd(abs(n), d)
        self.numerator = g == 0 ? 0 : n / g
        self.denominator = g == 0 ? 1 : d / g
    }

    var value: Double { Double(numerator) / Double(denominator) }

    static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    static func - (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator,
                 lhs.denominator * rhs.denominator)
    }

    static func < (lhs: Rational, rhs: Rational) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}

extension Rational {
    /// How far `event` advances the clock, in quarter notes.
    ///
    /// A duration in the model is a multiple of the voice's unit note length, so a quarter
    /// note is `4 × duration × L`.  Tuplets scale by `q/p`; everything untimed is zero.
    static func quarters(of event: Event, unitNoteLength: Fraction) -> Rational {
        let unit = Rational(4 * unitNoteLength.numerator, unitNoteLength.denominator)
        switch event {
        case .note(let n):  return unit * Rational(n.duration.numerator, n.duration.denominator)
        case .rest(let r):  return unit * Rational(r.duration.numerator, r.duration.denominator)
        case .chord(let c): return unit * Rational(c.duration.numerator, c.duration.denominator)
        case .tuplet(let t):
            // Summed the way `ColumnMetrics` sums it, so the merge and the sizer never
            // disagree about how long a tuplet is — a nested one included.
            let written = t.events.reduce(Rational.zero) { total, inner in
                switch inner {
                case .note(let n):  return total + Rational(n.duration.numerator, n.duration.denominator)
                case .rest(let r):  return total + Rational(r.duration.numerator, r.duration.denominator)
                case .chord(let c): return total + Rational(c.duration.numerator, c.duration.denominator)
                default:            return total
                }
            }
            return unit * written * Rational(t.q, t.p)
        default:
            return .zero
        }
    }

    static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }
}
