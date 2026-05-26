import CeolKitModel

/// Pass 4: assigns absolute page coordinates to every system, measure, and event.
///
/// Vertical extent is derived by scanning note pitches (treble-clef staff position),
/// chord symbols, annotations, and lyrics across each system's measures.
/// Systems fill pages top-to-bottom; a new page opens when the next system would exceed
/// the bottom margin.
public struct VerticalLayoutEngine: Sendable {
    private let config: SVGRenderConfig
    private let metadata: BravuraMetadata

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.config = config
        self.metadata = metadata
    }

    /// Converts justified systems into a fully positioned layout.
    ///
    /// - Parameters:
    ///   - systems: Pass 3 output.
    ///   - systemStartWidth: Horizontal space reserved before the first measure of each system
    ///     for clef, key signature, and time signature glyphs. The first measure's `origin.x`
    ///     is shifted right by this amount; subsequent measures follow immediately after.
    ///     Pass `0` when system-start glyphs are not needed (e.g. in tests).
    public func layout(
        _ systems: [JustifiedSystem],
        systemStartWidth: Double = 0
    ) -> ResolvedLayout {
        let staffHeight = 4.0 * config.staffSize

        var pages: [ResolvedPage] = []
        var pageSystems: [ResolvedSystem] = []
        var y = config.margins.top

        for jsystem in systems {
            let (extraAbove, extraBelow) = verticalExtent(of: jsystem)
            let totalHeight = extraAbove + staffHeight + extraBelow

            if !pageSystems.isEmpty && y + totalHeight > config.pageSize.height - config.margins.bottom {
                pages.append(ResolvedPage(systems: pageSystems))
                pageSystems = []
                y = config.margins.top
            }

            let systemOrigin = Point(x: config.margins.left, y: y)
            let measures = resolveMeasures(
                jsystem.measures,
                systemOrigin: systemOrigin,
                extraAbove: extraAbove,
                systemStartWidth: systemStartWidth
            )

            pageSystems.append(ResolvedSystem(
                origin: systemOrigin,
                measures: measures,
                staffOrigin: extraAbove,
                staffHeight: staffHeight,
                extraAbove: extraAbove,
                extraBelow: extraBelow,
                totalHeight: totalHeight
            ))

            y += totalHeight + config.systemGap
        }

        if !pageSystems.isEmpty {
            pages.append(ResolvedPage(systems: pageSystems))
        }

        return ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: pages
        )
    }

    // MARK: - Vertical extent

    private func verticalExtent(of system: JustifiedSystem) -> (extraAbove: Double, extraBelow: Double) {
        var maxLedgerAbove = 0
        var maxLedgerBelow = 0
        var hasChordSymbolsOrAnnotations = false
        var hasLyrics = false

        for jm in system.measures {
            for event in jm.source.measure.events {
                scan(
                    event,
                    maxLedgerAbove: &maxLedgerAbove,
                    maxLedgerBelow: &maxLedgerBelow,
                    hasChordSymbolsOrAnnotations: &hasChordSymbolsOrAnnotations,
                    hasLyrics: &hasLyrics
                )
            }
        }

        let s = config.staffSize
        let extraAbove = Double(maxLedgerAbove) * s + (hasChordSymbolsOrAnnotations ? s : 0)
        let extraBelow = Double(maxLedgerBelow) * s + (hasLyrics ? s * 2.0 : 0)
        return (extraAbove, extraBelow)
    }

    private func scan(
        _ event: Event,
        maxLedgerAbove: inout Int,
        maxLedgerBelow: inout Int,
        hasChordSymbolsOrAnnotations: inout Bool,
        hasLyrics: inout Bool
    ) {
        switch event {
        case .note(let n):
            accumulate(pitch: n.pitch, above: &maxLedgerAbove, below: &maxLedgerBelow)
            if n.chordSymbol != nil || !n.annotations.isEmpty { hasChordSymbolsOrAnnotations = true }
            if n.lyric != nil { hasLyrics = true }
        case .chord(let c):
            for n in c.notes { accumulate(pitch: n.pitch, above: &maxLedgerAbove, below: &maxLedgerBelow) }
            if c.chordSymbol != nil || !c.annotations.isEmpty { hasChordSymbolsOrAnnotations = true }
            if c.lyric != nil { hasLyrics = true }
        case .tuplet(let t):
            for e in t.events {
                scan(e,
                     maxLedgerAbove: &maxLedgerAbove,
                     maxLedgerBelow: &maxLedgerBelow,
                     hasChordSymbolsOrAnnotations: &hasChordSymbolsOrAnnotations,
                     hasLyrics: &hasLyrics)
            }
        case .grace(let g):
            for n in g.notes { accumulate(pitch: n.pitch, above: &maxLedgerAbove, below: &maxLedgerBelow) }
        default:
            break
        }
    }

    private func accumulate(pitch: Pitch, above: inout Int, below: inout Int) {
        let (a, b) = ledgerLines(for: pitch)
        above = max(above, a)
        below = max(below, b)
    }

    /// Returns the number of ledger lines required above and below the treble staff.
    ///
    /// Treble clef: bottom staff line = E4 (staff position 0), top staff line = F5 (position 8).
    /// A note on position 10 (A5) sits on the first ledger line above the staff.
    private func ledgerLines(for pitch: Pitch) -> (above: Int, below: Int) {
        let staffPos = (pitch.octave - 4) * 7 + (pitch.step.rawValue - DiatonicStep.e.rawValue)
        let above = max(0, (staffPos - 8) / 2)
        let below = max(0, (-staffPos) / 2)
        return (above, below)
    }

    // MARK: - Horizontal layout

    private func resolveMeasures(
        _ measures: [JustifiedMeasure],
        systemOrigin: Point,
        extraAbove: Double,
        systemStartWidth: Double
    ) -> [ResolvedMeasure] {
        var resolved: [ResolvedMeasure] = []
        var x = systemOrigin.x

        for (i, jm) in measures.enumerated() {
            let measureX = i == 0 ? x + systemStartWidth : x
            let measureOrigin = Point(x: measureX, y: systemOrigin.y)
            let eventBaseY = systemOrigin.y + extraAbove

            let events: [ResolvedEvent] = zip(jm.eventOffsets, jm.source.measure.events).map { offset, event in
                ResolvedEvent(
                    origin: Point(x: measureOrigin.x + offset, y: eventBaseY),
                    kind: ResolvedEventKind(from: event)
                )
            }

            let openingBar = jm.source.measure.openingBar.map {
                ResolvedBarLine(x: measureOrigin.x, kind: $0.kind)
            }
            let closingBar = ResolvedBarLine(
                x: measureOrigin.x + jm.finalWidth,
                kind: jm.source.measure.closingBar.kind
            )

            resolved.append(ResolvedMeasure(
                origin: measureOrigin,
                width: jm.finalWidth,
                events: events,
                openingBar: openingBar,
                closingBar: closingBar,
                unitNoteLength: jm.source.unitNoteLength
            ))

            x = measureOrigin.x + jm.finalWidth
        }

        return resolved
    }
}
