import CeolKitModel

/// Where the bar numbers `%%barnumbers` asks for stand over a system's top staff (ABC v2.2
/// §11.4.4; issue #290), worked out the way abcm2ps 8.14's `draw_measnb` (`deco.c`) does.
///
/// Written in two halves for the same reason ``EndingBracketBand`` is: the height a number
/// reaches is needed to size the staff's `extraAbove`, before anything has an x, and the x
/// is known only once the measures are placed.  ``marks(for:numbers:every:clef:stemDirection:style:boxed:staffSize:)``
/// does the first, ``place(_:over:staffLeftX:staffTopY:every:style:boxed:staffSize:)`` the
/// second.
///
/// abcm2ps's sizes are in its units, in which a staff space is 6; here `u` is one of those
/// units at the tune's staff size.
enum BarNumberBand {

    /// abcm2ps's `%%measurefont` default, "serif-italic 14", in its units (`format.c`).
    /// `%%measurefont` is not in the spec, so the number is always set in it.
    static let fontSize = 14.0

    /// One number, before it knows its x.
    struct Mark: Equatable, Sendable {
        let number: Int
        /// The measure whose closing bar line the number stands over, or `nil` for a number
        /// at the head of the system.
        let measure: Int?
        /// The number's baseline, measured up from the top staff line.
        let baseline: Double
    }

    /// The numbers drawn over a system's top staff.
    ///
    /// Each stands clear of the staff and of whatever ink of the staff's notes lies under
    /// it, as abcm2ps's skyline (`y_get`) keeps it; the x of that ink is taken from the
    /// justified measures, whose offsets are the ones the measures are placed with.
    ///
    /// - Parameters:
    ///   - numbers: the system's count, from ``BarNumbering``.
    ///   - every: the `%%barnumbers` value, `0` or more.
    ///   - stemDirection: which way the staff's first voice stems, where something has
    ///     decided it; `.auto` leaves it to each note's place on the staff.
    ///   - boxed: `%%measurebox`.  The box reaches 3 units below the baseline, so a boxed
    ///     number is raised by that much to keep the box as clear as the bare number.
    static func marks(for system: JustifiedSystem, numbers: BarNumbering.SystemNumbers,
                      every: Int, clef: ClefSpec, stemDirection: StemDirection,
                      style: TextStyle, boxed: Bool = false, staffSize: Double) -> [Mark] {
        guard every >= 0 else { return [] }
        let u = staffSize / TextStyles.nominalStaffSize
        let lift = boxed ? 3 * u : 0
        let pad = boxed ? 4 * u : 0
        let notes = noteInk(of: system, clef: clef, stemDirection: stemDirection,
                            staffSize: staffSize)
        /// The highest ink under `left…right`, measured up from the top staff line.  A unit
        /// of air either side keeps an italic digit's lean off a ledger line beside it.
        func skyline(_ left: Double, _ right: Double) -> Double {
            notes.inks.filter { $0.left < right + u && $0.right > left - u }
                .map { $0.top + 2 * u }.max() ?? -.infinity
        }
        var marks: [Mark] = []

        // The head of the system.  abcm2ps never numbers bar 1 there, which under
        // `%%measurefirst 1` is the first system.
        if numbers.start > 1 {
            if every == 0 {
                marks.append(Mark(number: numbers.start, measure: nil, baseline: 14 * u + lift))
            } else if numbers.start % every == 0 {
                let x = notes.barX.first ?? 0
                let width = style.width(of: String(numbers.start)) + pad
                marks.append(Mark(number: numbers.start, measure: nil,
                                  baseline: max(6 * u, skyline(x, x + width)) + 2 * u + lift))
            }
        }
        guard every > 0 else { return marks }

        // A number over every bar line opening a multiple of `every` — but not the system's
        // last, which abcm2ps leaves to the head of the next system, or the tune's end.
        for mi in system.measures.indices {
            guard mi + 1 < system.measures.count, mi < numbers.closing.count,
                  let number = numbers.closing[mi], number % every == 0 else { continue }
            let width = style.width(of: String(number)) + pad
            let left = notes.barX[mi + 1] - 0.4 * width
            var baseline = max(6 * u, skyline(left, left + width))
            // Raised over the note just after the bar line where it reaches higher: beside
            // an up stem the number may come down to a font size below its tip, and over
            // a down-stemmed note it clears the head's centre.
            if let next = notes.firstNote[mi + 1] {
                baseline = max(baseline, next.stemUp ? next.reach - fontSize * u : next.centre)
            }
            marks.append(Mark(number: number, measure: mi, baseline: baseline + 2 * u + lift))
        }
        return marks
    }

    /// How far above the top staff line the highest of `marks` reaches, or `0` for none:
    /// the digits' cap height, or the top of the box around them.
    static func reach(of marks: [Mark], style: TextStyle, boxed: Bool = false,
                      staffSize: Double) -> Double {
        let u = staffSize / TextStyles.nominalStaffSize
        let above = boxed ? boxAbove(style: style, u: u)
                          : style.size * LibertinusSerifMetrics.capHeightRatio
        return marks.map { $0.baseline + above }.max() ?? 0
    }

    /// How far the `%%measurebox` box reaches above the baseline, as abcm2ps's `showb`
    /// strokes it: four fifths of the font size, plus a unit.
    private static func boxAbove(style: TextStyle, u: Double) -> Double {
        0.8 * style.size + u
    }

    /// The numbers, placed on the page over the measures they were worked out for.
    static func place(_ marks: [Mark], over measures: [ResolvedMeasure],
                      staffLeftX: Double, staffTopY: Double, every: Int,
                      style: TextStyle, boxed: Bool, staffSize: Double) -> [BarNumber] {
        let u = staffSize / TextStyles.nominalStaffSize
        return marks.compactMap { mark in
            let text = String(mark.number)
            let textWidth = style.width(of: text)
            let x: Double
            switch mark.measure {
            case nil where every == 0:
                x = staffLeftX
            case nil:
                // abcm2ps stands it at the left of the first thing after the clef, key and
                // time signatures: the opening bar line where the system has one.
                guard let first = measures.first else { return nil }
                x = first.openingBar?.x ?? first.origin.x
            case let index?:
                guard index < measures.count else { return nil }
                let width = textWidth + (boxed ? 4 * u : 0)
                x = measures[index].closingBar.x - 0.4 * width
            }
            let baselineY = staffTopY - mark.baseline
            let box: Rect? = boxed
                ? Rect(origin: Point(x: x - 2 * u, y: baselineY - boxAbove(style: style, u: u)),
                       size: Size(width: textWidth + 4 * u, height: 0.8 * style.size + 4 * u))
                : nil
            return BarNumber(text: text, x: x, baselineY: baselineY, box: box)
        }
    }

    /// The ink of one note or chord, measured up from the top staff line.
    struct Ink {
        let left: Double
        let right: Double
        /// The top of its highest head, or of its stem where that goes up.
        let top: Double
    }

    /// What abcm2ps's explicit rule reads off the first note after a bar line.
    struct FirstNote {
        /// The centre of the highest head.
        let centre: Double
        /// The tip of the stem where it goes up, else the head's centre.
        let reach: Double
        let stemUp: Bool
    }

    /// The notes of `system` as a skyline: every note and chord of every voice on the
    /// staff, with x measured from the system's first measure; the x of every bar line (the
    /// opening one first, then each measure's closing one); and, per measure, its first
    /// voice's opening note, where it opens with one.
    static func noteInk(of system: JustifiedSystem, clef: ClefSpec, stemDirection: StemDirection,
                        staffSize s: Double)
        -> (inks: [Ink], barX: [Double], firstNote: [FirstNote?]) {
        var inks: [Ink] = []
        var barX: [Double] = [0]
        var firstNote: [FirstNote?] = []
        var clef = clef
        var measureX = 0.0
        for jm in system.measures {
            clef = jm.clef ?? clef
            let unit = jm.source.measure.unitNoteLength
            var opening: FirstNote?
            var seenFirst = false
            // A multi-measure rest stands at the centre of its bar (#300).
            let offsets = CentredRest.offsets(of: jm, measureLength: nil, metadata: nil,
                                              staffSize: s)
            for (index, event) in jm.source.measure.events.enumerated() {
                if case .clefChange(let change) = event { clef = change }
                let voice = index < jm.eventVoiceIndices.count ? jm.eventVoiceIndices[index] : 0
                let positions: [Int]
                let duration: Fraction
                switch event {
                case .note(let n):
                    positions = [clef.staffPosition(of: n.pitch)]
                    duration = n.duration
                case .chord(let c):
                    positions = c.notes.map { clef.staffPosition(of: $0.pitch) }
                    duration = c.duration
                case .grace, .spacer, .directiveAnchor, .tempoChange, .clefChange:
                    continue
                case .rest(let r) where MultiMeasureRest.drawnCount(of: r) != nil:
                    // Its count stands over the staff, the width of its bar (#291).
                    let u = s / TextStyles.nominalStaffSize
                    let x = measureX + (index < offsets.count ? offsets[index] : 0)
                    inks.append(Ink(left: x, right: x + MultiMeasureRest.barLength * u,
                                    top: MultiMeasureRest.reachAbove * u))
                    if voice == 0 { seenFirst = true }
                    continue
                default:
                    if voice == 0 { seenFirst = true }
                    continue
                }
                guard let high = positions.max(), let low = positions.min() else { continue }
                let stemUp: Bool
                switch stemDirection {
                case .up:   stemUp = true
                case .down: stemUp = false
                // The head furthest from the middle line decides, as for an unbeamed note.
                case .auto: stemUp = (high - 4) < (4 - low)
                }
                let whole = duration.numerator * unit.numerator
                    >= duration.denominator * unit.denominator
                let centre = Double(high - 8) / 2 * s
                let tip = stemUp && !whole ? Double(high - 8) / 2 * s + 3.5 * s : nil
                // abcm2ps's head reaches 4 of its units above its centre.
                let headTop = centre + 4 * s / TextStyles.nominalStaffSize
                let x = measureX + (index < jm.eventOffsets.count ? jm.eventOffsets[index] : 0)
                // Wide enough to take in a ledger line's overhang on either side.
                inks.append(Ink(left: x - 0.5 * s, right: x + (whole ? 2.2 : 1.7) * s,
                                top: max(headTop, tip ?? headTop)))
                if voice == 0 && !seenFirst {
                    seenFirst = true
                    opening = FirstNote(centre: centre, reach: tip ?? centre,
                                        stemUp: stemUp && tip != nil)
                }
            }
            firstNote.append(opening)
            measureX += jm.finalWidth
            barX.append(measureX)
        }
        return (inks, barX, firstNote)
    }
}
