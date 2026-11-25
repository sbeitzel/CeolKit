import CeolKitModel

/// Which bars of a tune are numbered, and with what — `%%barnumbers` / `%%measurenb` and
/// `%%measurefirst` (ABC v2.2 §11.4.4; issue #290).
///
/// The spec gives each directive one line, so the count is abcm2ps 8.14's (`set_bar_num` in
/// `parse.c`), which is a count of *time*, not of bar lines:
///
/// - A bar line counts only once a whole measure of the meter in force has passed since the
///   last one that counted, so a pickup is not bar 1, and the two halves of a bar split by a
///   repeat sign are one bar.  A tune with no meter counts every bar line.
/// - A multi-measure rest `Zn` (or `Xn`) is `n` bars.
/// - Each variant ending after the first (`:|2`, `[3`, …) starts again from the number the
///   first one began on.  abcm2ps's `%%contbarnb`, which turns that off, is not in the spec,
///   so CeolKit always restarts.
///
/// The count is taken on each system group's top staff, which is the one the numbers are
/// drawn over.
enum BarNumbering {

    /// The bar numbers of one system's top staff.
    struct SystemNumbers: Equatable, Sendable {
        /// The number of the bar the system opens with.
        let start: Int
        /// Per measure, the number of the bar its closing bar line opens, or `nil` where that
        /// bar line does not count — it closes an incomplete measure.
        let closing: [Int?]
    }

    /// The numbers of every system of a tune, in system order, counted from `first`.
    static func count(_ groups: [JustifiedSystemGroup], first: Int = 1) -> [SystemNumbers] {
        var counter = Counter(barNumber: first)
        var meter = groups.lazy.compactMap { $0.staves.first?.meter }.first
        var result: [SystemNumbers] = []
        result.reserveCapacity(groups.count)
        for (gi, group) in groups.enumerated() {
            guard let staff = group.staves.first else {
                result.append(SystemNumbers(start: counter.barNumber, closing: []))
                continue
            }
            if gi == 0, let opening = staff.measures.first?.source.measure {
                // abcm2ps's "bar at start of line": the tune's first measure may itself open
                // an ending, which is never counted but still takes part in the restarts.
                counter.openEndings(of: opening)
            }
            let start = counter.barNumber
            var closing: [Int?] = []
            closing.reserveCapacity(staff.measures.count)
            for (mi, jm) in staff.measures.enumerated() {
                if let changed = jm.source.measure.meter {
                    meter = changed
                    counter.changeMeter(to: Self.measureLength(changed))
                }
                let next = mi + 1 < staff.measures.count
                    ? staff.measures[mi + 1].source.measure
                    : groups[(gi + 1)...].lazy.compactMap { $0.staves.first?.measures.first }
                        .first?.source.measure
                closing.append(counter.close(jm, wmeasure: meter.flatMap(Self.measureLength),
                                             next: next))
            }
            result.append(SystemNumbers(start: start, closing: closing))
        }
        return result
    }

    /// The length of one measure of `meter` in whole notes, or `nil` for a meter that has
    /// none (`M:none`), under which every bar line counts.
    static func measureLength(_ meter: Meter) -> Double? {
        switch meter {
        case .fraction(let num, let den): return den > 0 ? Double(num) / Double(den) : nil
        case .commonTime:                 return 1
        case .cutTime:                    return 1
        case .complex(let parts, let den):
            return den > 0 ? Double(parts.reduce(0, +)) / Double(den) : nil
        case .free:                       return nil
        }
    }

    /// The walk's state: the clock, and when the next bar line will next count.
    private struct Counter {
        var barNumber: Int
        /// Where the first ending of the current set began.
        var repeatStart: Int
        var time = 0.0
        /// The time at or after which a bar line counts; `nil` until the first measure is
        /// closed, which sets it one measure from the start.
        var barTime: Double?

        init(barNumber: Int) {
            self.barNumber = barNumber
            self.repeatStart = barNumber
        }

        /// Restarts the count where `measure` opens a later ending, or remembers where the
        /// first began.  Only an ending standing at the bar line counts, as only a bar
        /// line does in abcm2ps.
        mutating func openEndings(of measure: Measure) {
            guard let ending = measure.endings.first, ending.startIndex == nil,
                  let number = ending.numbers.first else { return }
            if number == 1 { repeatStart = barNumber } else { barNumber = repeatStart }
        }

        /// A meter change at the start of the measure about to be closed.  As in abcm2ps, a
        /// change part way through a count restarts it from here.
        mutating func changeMeter(to wmeasure: Double?) {
            if let barTime, time < barTime { self.barTime = time + (wmeasure ?? 0) }
        }

        /// Advances over `jm` and returns the number its closing bar line opens, or `nil`
        /// where that bar line does not count.
        mutating func close(_ jm: JustifiedMeasure, wmeasure: Double?, next: Measure?) -> Int? {
            let length = wmeasure ?? 0
            if barTime == nil { barTime = time + length }
            let (duration, extraBars) = Self.duration(of: jm, wmeasure: length)
            time += duration
            barNumber += extraBars
            let epsilon = 1e-9
            guard time + epsilon >= barTime ?? 0 else { return nil }
            barNumber += 1
            if let next { openEndings(of: next) }
            barTime = time + length
            return barNumber
        }

        /// How long `jm`'s first voice lasts in whole notes, and how many bars beyond one a
        /// multi-measure rest in it stands for.
        static func duration(of jm: JustifiedMeasure, wmeasure: Double) -> (Double, Int) {
            let measure = jm.source.measure
            let unit = Double(measure.unitNoteLength.numerator)
                / Double(max(measure.unitNoteLength.denominator, 1))
            var total = 0.0
            for (index, event) in measure.events.enumerated() {
                let voice = index < jm.source.eventVoiceIndices.count
                    ? jm.source.eventVoiceIndices[index] : 0
                guard voice == 0 else { continue }
                if case .rest(let rest) = event, let bars = rest.measureCount {
                    return (max(total, wmeasure * Double(bars)), bars - 1)
                }
                total += units(of: event) * unit
            }
            return (total, 0)
        }

        private static func units(of event: Event) -> Double {
            switch event {
            case .note(let n):   return units(n.duration)
            case .rest(let r):   return units(r.duration)
            case .chord(let c):  return units(c.duration)
            case .tuplet(let t): return t.events.reduce(0) { $0 + units(of: $1) }
            default:             return 0
            }
        }

        private static func units(_ f: Fraction) -> Double {
            f.denominator == 0 ? 0 : Double(f.numerator) / Double(f.denominator)
        }
    }
}
