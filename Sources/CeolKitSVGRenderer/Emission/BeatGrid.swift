import CeolKitModel

/// Where a meter's beats and half-bars fall, so a stem on the middle line can follow the
/// stems sharing its beat or half-bar (#269).  Lengths are in whole notes.
struct BeatGrid {
    /// The beats of one bar, in order; nil under `M:none`, or with no meter, where a bar
    /// has no beats to go by.
    let beats: [Rational]?

    init(meter: Meter?) {
        switch meter {
        case .fraction(let num, let den) where num > 0 && den > 0:
            // A compound meter — 6/8, 9/8, 12/8, and the same over 16 — beats in dotted
            // notes, three of its units each; any other beats in its units.
            if den >= 8 && num > 3 && num % 3 == 0 {
                beats = Array(repeating: Rational(3, den), count: num / 3)
            } else {
                beats = Array(repeating: Rational(1, den), count: num)
            }
        case .commonTime:
            beats = Array(repeating: Rational(1, 4), count: 4)
        case .cutTime:
            beats = Array(repeating: Rational(1, 2), count: 2)
        case .complex(let groups, let den) where den > 0 && groups.allSatisfy({ $0 > 0 })
                                                 && !groups.isEmpty:
            beats = groups.map { Rational($0, den) }
        default:
            beats = nil
        }
    }

    /// How long a bar of the meter is; nil where it has no beats.
    var barLength: Rational? {
        beats?.reduce(Rational.zero, +)
    }

    /// Whether `a` and `b` — each a stretch of time from the head of the bar — sound in a
    /// segment in common, where the bar is cut into `segments`, repeated for a bar that
    /// runs longer than they do.
    static func overlap(_ a: (start: Rational, end: Rational),
                        _ b: (start: Rational, end: Rational),
                        segments: [Rational]) -> Bool {
        let first = segmentRange(a, segments: segments)
        let second = segmentRange(b, segments: segments)
        return first.overlaps(second)
    }

    /// The segments a stretch of time touches, by index: from the one it starts in to the
    /// one it ends in.  Its end is exclusive, so a note that fills a beat touches that beat
    /// alone.
    private static func segmentRange(_ span: (start: Rational, end: Rational),
                                     segments: [Rational]) -> ClosedRange<Int> {
        let first = segment(containing: span.start, segments: segments, atEnd: false)
        let last = span.end > span.start
            ? segment(containing: span.end, segments: segments, atEnd: true)
            : first
        return first...max(first, last)
    }

    /// The index of the segment that holds `time`: the one starting at or before it, or —
    /// for the end of a stretch — the one ending at or after it.
    private static func segment(containing time: Rational, segments: [Rational],
                                atEnd: Bool) -> Int {
        guard segments.contains(where: { $0 > .zero }) else { return 0 }
        var index = 0
        var boundary = Rational.zero
        while true {
            let next = boundary + segments[index % segments.count]
            if atEnd ? time <= next : time < next { return index }
            boundary = next
            index += 1
        }
    }
}
