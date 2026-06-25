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
    ///   - systems: The justified systems to lay out.
    ///   - titleRows: Pre-resolved title rows to embed on the first page.
    ///   - titleBlockHeight: Extra vertical space reserved at the top of the first page
    ///     for the title block. The first system's y-origin is shifted down by this amount.
    public func layout(
        _ systems: [JustifiedSystem],
        titleRows: [ResolvedTitleRow] = [],
        titleBlockHeight: Double = 0
    ) -> ResolvedLayout {
        let staffHeight = 4.0 * config.staffSize

        var pages: [ResolvedPage] = []
        var pageSystems: [ResolvedSystem] = []
        var isFirstPage = true
        var y = config.margins.top + titleBlockHeight

        for jsystem in systems {
            let (extraAbove, extraBelow) = verticalExtent(of: jsystem)
            let totalHeight = extraAbove + staffHeight + extraBelow

            if !pageSystems.isEmpty && y + totalHeight > config.pageSize.height - config.margins.bottom {
                let rows = isFirstPage ? titleRows : []
                pages.append(ResolvedPage(systems: pageSystems, titleRows: rows))
                pageSystems = []
                isFirstPage = false
                y = config.margins.top
            }

            let systemOrigin = Point(x: config.margins.left, y: y)
            let timeSigW = jsystem.meter.map {
                timeSignatureWidth(for: $0, metadata: metadata, staffSize: config.staffSize)
            } ?? 0
            // When no time signature follows, use noteheadWidth as the trailing gap after the key
            // signature so the space to the first bar line equals one note head.
            let keySigTrailing: Double? = timeSigW > 0 ? nil : {
                metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                    ?? config.staffSize * 1.2
            }()
            let keySigW = jsystem.keySignature.map {
                keySignatureWidth(for: $0, metadata: metadata, staffSize: config.staffSize,
                                  trailingGap: keySigTrailing)
            } ?? 0
            let startWidth = clefStartWidth(for: jsystem.clef) + keySigW + timeSigW
            let measures = resolveMeasures(
                jsystem.measures,
                systemOrigin: systemOrigin,
                extraAbove: extraAbove,
                systemStartWidth: startWidth
            )

            pageSystems.append(ResolvedSystem(
                origin: systemOrigin,
                measures: measures,
                staffOrigin: extraAbove,
                staffHeight: staffHeight,
                extraAbove: extraAbove,
                extraBelow: extraBelow,
                totalHeight: totalHeight,
                clef: jsystem.clef,
                keySignature: jsystem.keySignature,
                meter: jsystem.meter
            ))

            y += totalHeight + config.systemGap
        }

        if !pageSystems.isEmpty {
            let rows = isFirstPage ? titleRows : []
            pages.append(ResolvedPage(systems: pageSystems, titleRows: rows))
        }

        return ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: pages
        )
    }

    /// Lays out a sequence of tune blocks, each with its own optional title block.
    ///
    /// Tunes share pages when they fit; a new page opens only when the current page
    /// cannot accommodate a tune's title block and its first system together.
    /// Each tune's title rows are offset from their tune-relative `baselineY` values
    /// by the actual page y-origin at the moment they are placed.
    public func layout(_ tuneBlocks: [TuneBlock]) -> ResolvedLayout {
        let staffHeight = 4.0 * config.staffSize

        var pages: [ResolvedPage] = []
        var pageSystems: [ResolvedSystem] = []
        var pageTitleRows: [ResolvedTitleRow] = []
        var y = config.margins.top

        for block in tuneBlocks {
            // If the current page already has content, check whether the entire tune
            // fits in the remaining space. If not, close the current page. Tunes that
            // are taller than a full page are still forced to a fresh page here; the
            // inner system loop below handles the mid-tune page breaks they require.
            if !pageSystems.isEmpty {
                let tuneH = totalHeight(of: block)
                if y + tuneH > config.pageSize.height - config.margins.bottom {
                    pages.append(ResolvedPage(systems: pageSystems, titleRows: pageTitleRows))
                    pageSystems = []
                    pageTitleRows = []
                    y = config.margins.top
                }
            }

            // Place this tune's title rows, offsetting their tune-relative baselineY by y.
            for row in block.titleRows {
                pageTitleRows.append(ResolvedTitleRow(items: row.items.map {
                    ResolvedTitleRow.Item(
                        text: $0.text, x: $0.x, baselineY: $0.baselineY + y,
                        anchor: $0.anchor, fontSize: $0.fontSize, isItalic: $0.isItalic)
                }))
            }
            y += block.titleBlockHeight

            for (si, jsystem) in block.systems.enumerated() {
                let (extraAbove, extraBelow) = verticalExtent(of: jsystem)
                let totalHeight = extraAbove + staffHeight + extraBelow

                if !pageSystems.isEmpty && y + totalHeight > config.pageSize.height - config.margins.bottom {
                    pages.append(ResolvedPage(systems: pageSystems, titleRows: pageTitleRows))
                    pageSystems = []
                    pageTitleRows = []
                    y = config.margins.top
                }

                let systemOrigin = Point(x: config.margins.left, y: y)
                let timeSigW = jsystem.meter.map {
                    timeSignatureWidth(for: $0, metadata: metadata, staffSize: config.staffSize)
                } ?? 0
                let keySigTrailing: Double? = timeSigW > 0 ? nil : {
                    metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                        ?? config.staffSize * 1.2
                }()
                let keySigW = jsystem.keySignature.map {
                    keySignatureWidth(for: $0, metadata: metadata, staffSize: config.staffSize,
                                      trailingGap: keySigTrailing)
                } ?? 0
                let startWidth = clefStartWidth(for: jsystem.clef) + keySigW + timeSigW
                let measures = resolveMeasures(
                    jsystem.measures,
                    systemOrigin: systemOrigin,
                    extraAbove: extraAbove,
                    systemStartWidth: startWidth
                )
                pageSystems.append(ResolvedSystem(
                    origin: systemOrigin,
                    measures: measures,
                    staffOrigin: extraAbove,
                    staffHeight: staffHeight,
                    extraAbove: extraAbove,
                    extraBelow: extraBelow,
                    totalHeight: totalHeight,
                    clef: jsystem.clef,
                    keySignature: jsystem.keySignature,
                    meter: jsystem.meter
                ))
                let isLastInBlock = si == block.systems.count - 1
                y += totalHeight + (isLastInBlock ? config.tuneGap : config.systemGap)
            }
        }

        if !pageSystems.isEmpty || !pageTitleRows.isEmpty {
            pages.append(ResolvedPage(systems: pageSystems, titleRows: pageTitleRows))
        }

        return ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: pages
        )
    }

    // MARK: - Clef width

    /// Returns the total vertical space required to render `block` on a single page,
    /// including its title block, all systems, and inter-system gaps (but not the
    /// trailing gap that follows the last system).
    private func totalHeight(of block: TuneBlock) -> Double {
        let staffHeight = 4.0 * config.staffSize
        var h = block.titleBlockHeight
        for (i, jsystem) in block.systems.enumerated() {
            let (ea, eb) = verticalExtent(of: jsystem)
            h += ea + staffHeight + eb
            if i < block.systems.count - 1 { h += config.systemGap }
        }
        return h
    }

    private func clefStartWidth(for spec: ClefSpec) -> Double {
        clefHeaderWidth(for: spec, metadata: metadata, staffSize: config.staffSize)
    }

    // MARK: - Vertical extent

    private func verticalExtent(of system: JustifiedSystem) -> (extraAbove: Double, extraBelow: Double) {
        var maxLedgerAbove = 0
        var maxLedgerBelow = 0
        var hasChordSymbolsOrAnnotations = false
        var hasLyrics = false
        var hasGraceGroups = false

        for jm in system.measures {
            for event in jm.source.measure.events {
                scan(
                    event,
                    maxLedgerAbove: &maxLedgerAbove,
                    maxLedgerBelow: &maxLedgerBelow,
                    hasChordSymbolsOrAnnotations: &hasChordSymbolsOrAnnotations,
                    hasLyrics: &hasLyrics,
                    hasGraceGroups: &hasGraceGroups
                )
            }
        }

        let s = config.staffSize
        // Grace note stems always point upward (graceScale=0.6) × 3.5 staff spaces above the
        // notehead. Reserve that height so stems never intrude into the title block zone.
        let graceOvershoot = hasGraceGroups ? 3.5 * s * 0.6 : 0
        let extraAbove = Double(maxLedgerAbove) * s + (hasChordSymbolsOrAnnotations ? s : 0) + graceOvershoot
        let extraBelow = Double(maxLedgerBelow) * s + (hasLyrics ? s * 2.0 : 0)
        return (extraAbove, extraBelow)
    }

    private func scan(
        _ event: Event,
        maxLedgerAbove: inout Int,
        maxLedgerBelow: inout Int,
        hasChordSymbolsOrAnnotations: inout Bool,
        hasLyrics: inout Bool,
        hasGraceGroups: inout Bool
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
                     hasLyrics: &hasLyrics,
                     hasGraceGroups: &hasGraceGroups)
            }
        case .grace(let g):
            hasGraceGroups = true
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

            // At the start of a system (i == 0), suppress any opening bar that was
            // inherited from the previous system's closing bar (e.g. a lone `|`).
            // Only explicit section-start markers ([|, [|:, |:, ::) are drawn at a
            // system start; everything else would appear as a spurious bar line between
            // the clef/key signature and the first note.
            let openingBar: ResolvedBarLine?
            if i == 0, let bar = jm.source.measure.openingBar {
                switch bar.kind {
                case .start, .sectionRepeatStart, .repeatStart, .repeatBoth:
                    openingBar = ResolvedBarLine(x: measureOrigin.x, kind: bar.kind)
                default:
                    openingBar = nil
                }
            } else {
                openingBar = jm.source.measure.openingBar.map {
                    ResolvedBarLine(x: measureOrigin.x, kind: $0.kind)
                }
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
                unitNoteLength: jm.source.unitNoteLength,
                meter: jm.source.measure.meter
            ))

            x = measureOrigin.x + jm.finalWidth
        }

        return resolved
    }
}
