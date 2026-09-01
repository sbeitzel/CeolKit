import CeolKitModel

/// The band of space above a staff that variant-ending brackets stand in — `|1`, `|2`,
/// `[1,2`, `|1-3` (ABC v2.2 §4.19) — and the runs of measures each bracket covers.
///
/// Written as one calculation for the same reason ``LyricBand`` is: the space is reserved in
/// one pass and drawn into in another.  ``VerticalLayoutEngine`` adds
/// ``height(staffSize:)`` to the staff's `extraAbove` and places the brackets against the top
/// of the band it just reserved; the emitter draws what it is handed.  A staff whose measures
/// carry no ending number reserves nothing and draws nothing, which is what keeps every page
/// of every tune without variant endings exactly as it was.
///
/// The runs are worked out here rather than in the emitter because they are not a property of
/// one system: the parser tags only the *first* measure of an ending (`pendingEndingNumber` is
/// cleared as soon as a bar closes), so where the ending stops has to be inferred from the bar
/// lines that follow — and an ending long enough to cross a line break has to be carried from
/// one system to the next, which only the pass that sees the systems in order can do.
enum EndingBracketBand {

    // MARK: - Metrics

    /// Label size as a multiple of the staff space: abcm2ps sets `%%repeatfont serif 13`
    /// against its 6-point staff space, which is the ratio ``LyricBand/fontSizeRatio``
    /// is derived from for `%%vocalfont`.
    static let fontSizeRatio = 13.0 / 6.0

    /// Air above the label's cap line, and again below its baseline before the hook ends.
    static let labelPadRatio = 0.25

    /// Gap between the foot of the hooks and whatever the staff reaches up to below them —
    /// its ledger lines, its chord symbols, the tip of a grace note's stem.
    static let clearanceRatio = 0.5

    /// How far the label stands right of the bracket's left edge, so it clears the hook.
    static let labelInsetRatio = 0.4

    static func fontSize(staffSize: Double) -> Double { fontSizeRatio * staffSize }

    /// Thickness of the rule and of the hooks that drop from it.
    static func thickness(metadata: BravuraMetadata, staffSize: Double) -> Double {
        metadata.engravingDefaults.repeatEndingLineThickness * staffSize
    }

    /// Baseline of the label, measured down from the rule.  Digits have no descender and
    /// reach cap height, so that is what the pad is measured against.
    static func labelBaselineOffset(staffSize: Double) -> Double {
        labelPadRatio * staffSize
            + fontSize(staffSize: staffSize) * LibertinusSerifMetrics.capHeightRatio
    }

    /// How far the hooks drop below the rule — far enough to enclose the label.
    static func hookDepth(staffSize: Double) -> Double {
        labelBaselineOffset(staffSize: staffSize) + labelPadRatio * staffSize
    }

    /// Space a staff carrying a bracket needs above everything else it reaches up to.
    static func height(staffSize: Double) -> Double {
        hookDepth(staffSize: staffSize) + clearanceRatio * staffSize
    }

    static func labelInset(staffSize: Double) -> Double { labelInsetRatio * staffSize }

    /// What a bracket covering `numbers` is labelled.
    ///
    /// The list, comma-separated, whatever it was written as: the semantic pass resolves
    /// `|1-3` to `[1, 2, 3]` and keeps no record of the range it came from, so `|1,2,3` and
    /// `|1-3` are the same ending and are labelled the same way.
    static func label(for numbers: [Int]) -> String {
        numbers.map(String.init).joined(separator: ",")
    }

    // MARK: - Runs

    /// One bracket, before it knows where on the page it goes: which of a staff-system's
    /// measures it covers, and how it is terminated at each end.
    struct Run: Equatable, Sendable {
        /// The number(s) printed at the bracket's left end, or `nil` on the continuation of
        /// an ending that opened on an earlier system — the number is printed once, where
        /// the ending begins.
        let label: String?
        /// Indices into the staff-system's measures, inclusive.
        let firstMeasure: Int
        let lastMeasure: Int
        /// Whether the rule turns down at its left end.  False exactly where the ending was
        /// carried over a system break.
        let hasStartHook: Bool
        /// Whether the rule turns down at its right end: it does at the repeat bar that
        /// sends the player back, and does not where the music runs on — into the next
        /// ending, past a final bar line, or over a system break.
        let hasEndHook: Bool
    }

    /// The runs of every staff of every system of one tune, indexed `[system][staff]`.
    ///
    /// Walked in system order per staff so that an ending crossing a line break is carried:
    /// the continuation draws a bracket with no left hook and no label, which is what says
    /// it is the same ending rather than a new one.
    static func runs(in groups: [JustifiedSystemGroup]) -> [[[Run]]] {
        // What each staff has left open at the end of the system just walked.
        var carried: [Int: [Int]] = [:]
        var result: [[[Run]]] = []
        result.reserveCapacity(groups.count)
        for group in groups {
            var perStaff: [[Run]] = []
            perStaff.reserveCapacity(group.staves.count)
            for (index, staff) in group.staves.enumerated() {
                let (runs, trailing) = self.runs(
                    in: staff.measures.map(\.source.measure), continuing: carried[index])
                carried[index] = trailing
                perStaff.append(runs)
            }
            // A `%%score` in the tune body can change the staff count part-way through
            // (`PlanRegions`); an ending left open on a staff the next region does not print
            // has nothing to continue onto.
            carried = carried.filter { $0.key < group.staves.count }
            result.append(perStaff)
        }
        return result
    }

    /// The runs of one staff-system, and the ending it leaves open for the next one.
    ///
    /// - Parameter continuing: the ending running into this system from the previous one,
    ///   `nil` where none is.
    static func runs(in measures: [Measure],
                     continuing: [Int]?) -> (runs: [Run], trailing: [Int]?) {
        struct Open {
            let numbers: [Int]
            let first: Int
            let startHook: Bool
        }

        var runs: [Run] = []
        var open: Open?
        if let continuing, !measures.isEmpty {
            open = Open(numbers: continuing, first: 0, startHook: false)
        }

        func close(_ o: Open, at last: Int, endHook: Bool) -> Run {
            Run(label: o.startHook ? label(for: o.numbers) : nil,
                firstMeasure: o.first, lastMeasure: last,
                hasStartHook: o.startHook, hasEndHook: endHook)
        }

        for (i, measure) in measures.enumerated() {
            if let numbers = measure.endingNumber {
                // The next ending begins.  Anything still open ends at the measure before it,
                // unhooked: the music runs straight on into the new ending.
                if let o = open, i > o.first { runs.append(close(o, at: i - 1, endHook: false)) }
                open = Open(numbers: numbers, first: i, startHook: true)
            }
            guard let o = open else { continue }
            switch measure.closingBar.kind {
            case .repeatEnd, .repeatBoth, .repeatEndSection:
                // The bar that sends the player back is what the bracket is drawn for; it
                // closes with a hook.
                runs.append(close(o, at: i, endHook: true))
                open = nil
            case .final, .double, .start, .sectionRepeatStart, .repeatStart:
                // The section is over — the last ending of a repeat ends here — but nothing
                // is being repeated from this bar, so the bracket is left open.
                runs.append(close(o, at: i, endHook: false))
                open = nil
            case .single, .dotted:
                break  // the ending runs on into the next measure
            }
        }

        // An ending still open at the end of the system runs into the next one: draw what
        // there is of it, open at the right, and hand the rest on.
        if let o = open { runs.append(close(o, at: measures.count - 1, endHook: false)) }
        return (runs, open?.numbers)
    }

    // MARK: - Placement

    /// Places `runs` over `measures`, whose x positions are already resolved.
    ///
    /// `bandTopY` is the top of the staff's own band — the brackets stand at the very top of
    /// it, above the ledger lines and annotations the rest of `extraAbove` was reserved for.
    static func place(_ runs: [Run], over measures: [ResolvedMeasure],
                      bandTopY: Double, staffSize: Double,
                      metadata: BravuraMetadata) -> [EndingBracket] {
        // The rule is stroked centred on its y, so half of it sits above `ruleY`; starting
        // half a thickness down keeps it inside the band that was reserved for it.
        let ruleY = bandTopY + thickness(metadata: metadata, staffSize: staffSize) / 2
        return runs.compactMap { run in
            guard measures.indices.contains(run.firstMeasure),
                  measures.indices.contains(run.lastMeasure) else { return nil }
            let last = measures[run.lastMeasure]
            return EndingBracket(
                label: run.label,
                startX: measures[run.firstMeasure].origin.x,
                endX: last.origin.x + last.width,
                ruleY: ruleY,
                hasStartHook: run.hasStartHook,
                hasEndHook: run.hasEndHook)
        }
    }
}
