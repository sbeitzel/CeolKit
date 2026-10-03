/// Pass 3: distributes horizontal slack across measures so each non-last system
/// fills the full usable line width.
///
/// Two things stop that from being unconditional.  A system whose music overruns the line —
/// which the `LineBreaker` now allows within its overflow tolerance — is compressed to fit
/// instead, last system or not.  And a system the breaker itself created by splitting an
/// over-long stave is stretched no further than ``maxStretch``, so an unavoidably near-empty
/// system is left short rather than smeared across the page.
public struct Justifier: Sendable {

    /// The most a system whose width the line breaker chose — one from a stave it had to
    /// split — may be stretched, as a multiple of its natural width.  Past this the system is
    /// left short and aligned to the left margin rather than pulled across the page.
    ///
    /// Deliberately generous.  Filling the line is the normal thing to do with the halves of
    /// a split stave, and a stave that is a hair over one line balances into two systems that
    /// each need ~2× to fill, so anything near 2 would leave ordinary music ragged.  The cap
    /// exists for the case balancing cannot reach — a stave of one long measure and one short
    /// one, where the short system would otherwise be smeared across the whole page.  At `3`
    /// it only engages below a third of the line, and a system that empty *should* look short.
    ///
    /// A system the *source* asked for (a line the writer chose to end early) is never
    /// capped: stretching those to the full line is standard practice, and asked for.
    public let maxStretch: Double

    public init(maxStretch: Double = 3.0) {
        self.maxStretch = max(1, maxStretch)
    }

    /// Justifies `systems` so each fills the available measure width.
    ///
    /// - Parameters:
    ///   - systems: Pass 2 output.
    ///   - usableWidth: Full available horizontal space (page width minus margins).
    ///   - justifyLastSystem: When `true`, the last system is also stretched to fill the line.
    ///   - systemHeaderWidths: Per-system width consumed by clef/key/time-sig headers.
    ///     The target width for system `i` is `usableWidth - systemHeaderWidths[i]`.
    ///     Defaults to zero for any system not covered by the array.
    public func justify(
        _ systems: [System],
        usableWidth: Double,
        justifyLastSystem: Bool,
        systemHeaderWidths: [Double] = []
    ) -> [JustifiedSystem] {
        justifyGroups(systems.map { SystemGroup(staves: [$0]) },
                      usableWidth: usableWidth,
                      justifyLastSystem: justifyLastSystem,
                      systemHeaderWidths: systemHeaderWidths)
            .map { $0.staves[0] }
    }

    /// Justifies `groups`, giving every staff of a group the same measure x-positions.
    ///
    /// A column's final width is derived once, from the widest staff's natural width for
    /// that column, and handed to every staff in the group.  That is what makes the bar
    /// lines line up vertically: a staff whose measure is narrower than the column simply
    /// gets more slack distributed inside it.
    ///
    /// - Parameters:
    ///   - groups: Pass 2 output.
    ///   - usableWidth: Full available horizontal space (page width minus margins).
    ///   - justifyLastSystem: When `true`, the last system is also stretched to fill the line.
    ///   - systemHeaderWidths: Per-system width consumed by clef/key/time-sig headers —
    ///     already the `max` across the group's voices, since its staves start at a common x.
    ///   - systemUsableWidths: Per-system line width, where the systems of one tune do not all
    ///     have the same one.  A `%%landscape` at a `%%newpage` turns the page part-way
    ///     through a tune (issue #158), and the systems after it fill a wider — or narrower —
    ///     line than the ones before.  An entry overrides `usableWidth` for that system;
    ///     anything the array does not cover falls back to it, which is every system of every
    ///     tune that keeps one orientation throughout.
    /// Named rather than overloaded on the element type: `justify([])` would otherwise be
    /// ambiguous, which is a trap for a call site that has nothing to justify.
    public func justifyGroups(
        _ groups: [SystemGroup],
        usableWidth: Double,
        justifyLastSystem: Bool,
        systemHeaderWidths: [Double] = [],
        systemUsableWidths: [Double] = []
    ) -> [JustifiedSystemGroup] {
        groups.enumerated().map { i, group in
            let headerWidth = i < systemHeaderWidths.count ? systemHeaderWidths[i] : 0
            let lineWidth = i < systemUsableWidths.count ? systemUsableWidths[i] : usableWidth
            let targetWidth = lineWidth - headerWidth
            let shouldStretch = !group.isLastSystem || justifyLastSystem
            return justify(group, targetWidth: targetWidth, stretch: shouldStretch,
                           capStretch: group.staveWasSplit)
        }
    }

    // MARK: - Private

    private func justify(_ group: SystemGroup, targetWidth: Double, stretch: Bool,
                         capStretch: Bool) -> JustifiedSystemGroup {
        // A column is as wide as its widest staff needs; every staff is then drawn to that.
        let columnWidths = (0..<group.columnCount).map { column in
            group.staves.reduce(0.0) { max($0, $1.measures[column].naturalWidth) }
        }
        let naturalTotal = columnWidths.reduce(0, +)
        let finalTotal = resolvedWidth(naturalTotal: naturalTotal, targetWidth: targetWidth,
                                       stretch: stretch, capStretch: capStretch)

        // What the music alone would have made each column, before text widened it.
        let musicWidths = (0..<group.columnCount).map { column in
            group.staves.reduce(0.0) { max($0, $1.measures[column].musicWidth) }
        }

        let finalWidths: [Double]
        if finalTotal > naturalTotal, zip(musicWidths, columnWidths).contains(where: { $0 < $1 }) {
            // Some column was widened for its text (issue #185).  Stretch the music and hold
            // each column to the width its text needs, rather than scaling the text's room up
            // along with it: a bar that had to open up for one long chord symbol should not
            // then take the lion's share of the line's slack as well.
            let scale = Self.floorScale(music: musicWidths, floors: columnWidths,
                                        target: finalTotal)
            finalWidths = zip(musicWidths, columnWidths).map { max($0 * scale, $1) }
        } else if naturalTotal > 0 && finalTotal != naturalTotal {
            let slack = finalTotal - naturalTotal
            finalWidths = columnWidths.map { $0 + slack * ($0 / naturalTotal) }
        } else {
            // Nothing to redistribute: keep natural widths (left-aligned).
            finalWidths = columnWidths
        }

        let staves = group.staves.map { staff -> JustifiedSystem in
            let measures = staff.measures.enumerated().map { column, sized -> JustifiedMeasure in
                let finalWidth = finalWidths[column]
                guard finalWidth != sized.naturalWidth else {
                    return JustifiedMeasure(source: sized, finalWidth: finalWidth,
                                            eventOffsets: sized.eventOffsets)
                }
                let widenedForText = sized.musicOffsets != sized.eventOffsets
                    || sized.musicWidth != sized.naturalWidth
                let offsets = widenedForText && finalWidth > sized.naturalWidth
                    ? stretchOffsets(of: sized, finalWidth: finalWidth)
                    : stretchOffsets(sized.eventOffsets,
                                     naturalWidth: sized.naturalWidth,
                                     finalWidth: finalWidth,
                                     graceIndices: sized.graceEventIndices)
                return JustifiedMeasure(source: sized, finalWidth: finalWidth, eventOffsets: offsets)
            }
            return JustifiedSystem(measures: measures, isLastSystem: staff.isLastSystem,
                                   sourceForced: staff.sourceForced, clef: staff.clef,
                                   keySignature: staff.keySignature, meter: staff.meter,
                                   voiceLabel: staff.voiceLabel,
                                   voiceStemDirections: staff.voiceStemDirections,
                                   headerKeyChange: staff.headerKeyChange)
        }
        return JustifiedSystemGroup(staves: staves, grouping: group.grouping)
    }

    /// The width the system's music is laid out to.
    ///
    /// A system that overruns is squeezed back onto the line whether or not it would
    /// otherwise be stretched — music must not cross the right margin, and the line breaker
    /// now hands over systems that deliberately overrun by a percent or two.
    private func resolvedWidth(naturalTotal: Double, targetWidth: Double,
                               stretch: Bool, capStretch: Bool) -> Double {
        if naturalTotal > targetWidth { return targetWidth }
        guard stretch else { return naturalTotal }
        guard capStretch else { return targetWidth }
        return min(targetWidth, naturalTotal * maxStretch)
    }

    /// Stretches `offsets` from `naturalWidth` to `finalWidth` while keeping the gap within
    /// each grace+note pair fixed.  All horizontal slack goes to elastic (note-to-note) spacings.
    ///
    /// The elastic scale factor is derived from the *elastic* portion of the measure width:
    /// `naturalWidth` minus the leading margin (`base`) and all fixed grace-to-note gaps
    /// (`fixedTotal`).  Grace events (identified by `graceIndices`) stay fixed relative to
    /// the note they precede; every other event is scaled proportionally.
    ///
    /// How much fixed width lies to an event's left is asked of the *offsets*, not of the
    /// array order.  On a single-voice measure the two agree, because offsets only ever
    /// increase.  A shared staff (§11.1 `( … )`) is where they part: its events are ordered
    /// voice by voice within each onset so that no grace group is separated from its note,
    /// which means the array steps backwards every time a new voice starts its run.
    private func stretchOffsets(_ offsets: [Double], naturalWidth: Double, finalWidth: Double,
                                 graceIndices: Set<Int>) -> [Double] {
        guard !offsets.isEmpty else { return offsets }
        let base = offsets[0]

        // One entry per grace+note pair: where its note sits, and the incompressible gap
        // between the two.
        let pairs: [(note: Int, x: Double, gap: Double)] = graceIndices.sorted().compactMap {
            guard $0 + 1 < offsets.count else { return nil }
            return (note: $0 + 1, x: offsets[$0 + 1], gap: offsets[$0 + 1] - offsets[$0])
        }
        let fixedTotal = pairs.reduce(0.0) { $0 + $1.gap }

        let elasticNatural = naturalWidth - base - fixedTotal
        guard elasticNatural > 0 else { return offsets }
        // Compression never runs the elastic spacings past zero: the fixed parts of the
        // measure are incompressible, so there is nothing sane to do below that point.
        let elasticScale = max(0, (finalWidth - base - fixedTotal) / elasticNatural)

        /// The fixed width of every grace pair that finishes to the left of event `i`.
        /// Ties — a zero-width column, or a second voice sounding at the same x — are broken
        /// by array position, which is what the single-voice walk this replaces did.
        func fixedLeftOf(_ i: Int) -> Double {
            pairs.reduce(0.0) { sum, pair in
                guard pair.note != i, pair.note - 1 != i else { return sum }
                let isLeft = pair.x < offsets[i] || (pair.x == offsets[i] && pair.note < i)
                return isLeft ? sum + pair.gap : sum
            }
        }

        var result = [Double](repeating: 0, count: offsets.count)
        for i in 0..<offsets.count {
            if i > 0 && graceIndices.contains(i - 1) {
                // Pair-follower: preserve the fixed gap from the preceding grace event.
                result[i] = result[i - 1] + (offsets[i] - offsets[i - 1])
            } else {
                // Elastic event: scale its position relative to the base.
                let fixed = fixedLeftOf(i)
                result[i] = base + fixed + (offsets[i] - base - fixed) * elasticScale
            }
        }
        return result
    }

    // MARK: - Stretching around text (issue #185)

    /// The factor `k` at which `Σ max(music[g] · k, floors[g])` reaches `target`.
    ///
    /// Each gap is stretched with the music, but never below the width it already has
    /// (`floors[g] ≥ music[g]`); a gap the text widened therefore takes no slack until the
    /// music around it has caught up with it.  `target` is at least `Σ floors`, which is the
    /// sum at `k = 1`.  Where nothing can stretch at all, `1`.
    static func floorScale(music: [Double], floors: [Double], target: Double) -> Double {
        // A gap joins the stretch at the factor where its music overtakes its floor.
        /// Where a gap joins: never, for one with no music to stretch.
        func joinsAt(_ gap: (music: Double, floor: Double)) -> Double {
            gap.music > 0 ? gap.floor / gap.music : .infinity
        }
        let gaps: [(music: Double, floor: Double)] = zip(music, floors)
            .map { (music: $0.0, floor: max($0.0, $0.1)) }
            .sorted { joinsAt($0) < joinsAt($1) }
        var stretching = 0.0                                // Σ music of the gaps stretching
        var held = gaps.reduce(0.0) { $0 + $1.floor }       // Σ floor of the gaps that are not
        for gap in gaps {
            guard gap.music > 0 else { break }
            if stretching > 0 {
                let k = (target - held) / stretching
                if k <= joinsAt(gap) { return max(1, k) }
            }
            stretching += gap.music
            held -= gap.floor
        }
        guard stretching > 0 else { return 1 }
        return max(1, (target - held) / stretching)
    }

    /// Stretches a bar that ``AnnotationSpacing`` widened, from its natural width to
    /// `finalWidth`.
    ///
    /// As ``stretchOffsets(_:naturalWidth:finalWidth:graceIndices:)`` does, the leading
    /// margin and each grace+note gap stay fixed and everything else is elastic.  The
    /// elastic gaps, though, are stretched from their *music* widths and held to at least
    /// their widened ones — see ``floorScale(music:floors:target:)`` — so the room a chord
    /// symbol needed is kept, not scaled up again with everything else.
    private func stretchOffsets(of sized: SizedMeasure, finalWidth: Double) -> [Double] {
        let offsets = sized.eventOffsets
        let music = sized.musicOffsets
        guard !offsets.isEmpty, music.count == offsets.count else { return offsets }
        let graceIndices = sized.graceEventIndices
        let base = offsets[0]

        let pairs: [(note: Int, x: Double, gap: Double)] = graceIndices.sorted().compactMap {
            guard $0 + 1 < offsets.count else { return nil }
            return (note: $0 + 1, x: offsets[$0 + 1], gap: offsets[$0 + 1] - offsets[$0])
        }
        let fixedTotal = pairs.reduce(0.0) { $0 + $1.gap }
        func fixedLeftOf(_ i: Int) -> Double {
            pairs.reduce(0.0) { sum, pair in
                guard pair.note != i, pair.note - 1 != i else { return sum }
                let isLeft = pair.x < offsets[i] || (pair.x == offsets[i] && pair.note < i)
                return isLeft ? sum + pair.gap : sum
            }
        }

        // Every elastic event's coordinate along the elastic part of the bar, as widened and
        // as the music alone placed it.
        let elastic = offsets.indices.filter { !($0 > 0 && graceIndices.contains($0 - 1)) }
        let widened = Dictionary(uniqueKeysWithValues: elastic.map {
            ($0, offsets[$0] - base - fixedLeftOf($0))
        })
        let unwidened = Dictionary(uniqueKeysWithValues: elastic.map {
            ($0, music[$0] - music[0] - fixedLeftOf($0))
        })

        // The distinct points the elastic events stand at, left to right, and the bar's end.
        var points: [(widened: Double, music: Double)] = []
        for i in elastic.sorted(by: { (widened[$0]!, $0) < (widened[$1]!, $1) }) {
            let point = (widened: widened[i]!, music: unwidened[i]!)
            if let last = points.last, abs(last.widened - point.widened) < 0.0001 {
                points[points.count - 1].music = max(last.music, point.music)
            } else {
                points.append(point)
            }
        }
        points.append((widened: sized.naturalWidth - base - fixedTotal,
                       music: sized.musicWidth - music[0] - fixedTotal))

        let floors = zip(points, points.dropFirst()).map { $1.widened - $0.widened }
        let musicGaps = zip(zip(points, points.dropFirst()), floors).map { pair, floor in
            min(floor, max(0, pair.1.music - pair.0.music))
        }
        let scale = Self.floorScale(music: musicGaps, floors: floors,
                                    target: finalWidth - base - fixedTotal)

        // Where each point lands once every gap before it has been stretched.
        var landed: [Double] = [points.first?.widened ?? 0]
        for (m, floor) in zip(musicGaps, floors) {
            landed.append(landed[landed.count - 1] + max(m * scale, floor))
        }
        func landing(_ coordinate: Double) -> Double {
            let n = points.firstIndex { abs($0.widened - coordinate) < 0.0001 } ?? 0
            return landed[n]
        }

        var result = [Double](repeating: 0, count: offsets.count)
        for i in 0..<offsets.count {
            if i > 0 && graceIndices.contains(i - 1) {
                result[i] = result[i - 1] + (offsets[i] - offsets[i - 1])
            } else {
                result[i] = base + fixedLeftOf(i) + landing(widened[i]!)
            }
        }
        return result
    }
}
