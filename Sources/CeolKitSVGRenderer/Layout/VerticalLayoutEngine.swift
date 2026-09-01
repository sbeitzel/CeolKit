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
    /// The text face voice labels are measured in, or `nil` where none was supplied or it
    /// could not be read.  ``VoiceLabelGutter`` falls back to an estimate, and the caller
    /// that reserved the gutter took the same fallback, so the two still agree.
    private let labelFont: OpenTypeFont?

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.init(config: config, metadata: metadata, labelFont: nil)
    }

    init(config: SVGRenderConfig, metadata: BravuraMetadata, labelFont: OpenTypeFont?) {
        self.config = config
        self.metadata = metadata
        self.labelFont = labelFont
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
        var previousAbcLine: Int?

        for jsystem in systems {
            let (extraAbove, extraBelow) = verticalExtent(of: jsystem, staffSize: config.staffSize)
            let totalHeight = extraAbove + staffHeight + extraBelow

            if !pageSystems.isEmpty && y + totalHeight > config.pageSize.height - config.margins.bottom {
                let rows = isFirstPage ? titleRows : []
                pages.append(ResolvedPage(systems: pageSystems, titleRows: rows))
                pageSystems = []
                isFirstPage = false
                y = config.margins.top
            }

            let systemOrigin = Point(x: config.margins.left, y: y)
            let startWidth = systemStartWidth(for: jsystem, staffSize: config.staffSize)
            let measures = resolveMeasures(
                jsystem.measures,
                systemOrigin: systemOrigin,
                extraAbove: extraAbove,
                systemStartWidth: startWidth
            )

            let abcLine = resolvedAbcLine(of: jsystem, previous: previousAbcLine)
            previousAbcLine = abcLine
            pageSystems.append(ResolvedSystem(
                origin: systemOrigin,
                measures: measures,
                staffOrigin: extraAbove,
                staffSize: config.staffSize,
                staffHeight: staffHeight,
                graceNoteSpacing: config.graceNoteSpacing,
                extraAbove: extraAbove,
                extraBelow: extraBelow,
                totalHeight: totalHeight,
                clef: jsystem.clef,
                keySignature: jsystem.keySignature,
                meter: jsystem.meter,
                abcLine: abcLine
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
        var pages: [ResolvedPage] = []
        var pageSystems: [ResolvedSystem] = []
        var pageTitleRows: [ResolvedTitleRow] = []
        var y = config.margins.top
        var previousAbcLine: Int?

        for block in tuneBlocks {
            let groups = block.systemGroups
            // %%ceolkit:scale sizes this tune's music (and the gaps derived from staffSize)
            // relative to the renderer default. Page size and margins stay absolute.
            let tuneConfig  = config.scaled(by: block.scale)
            let staffSize   = tuneConfig.staffSize
            let staffHeight = 4.0 * staffSize
            let systemGap   = tuneConfig.systemGap
            let tuneGap     = tuneConfig.tuneGap

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

            for (gi, group) in groups.enumerated() {
                let metrics = groupMetrics(of: group, config: tuneConfig)

                // A group breaks to the next page whole: splitting it would separate staves
                // that only mean anything read together.
                if !pageSystems.isEmpty && y + metrics.totalHeight > config.pageSize.height - config.margins.bottom {
                    pages.append(ResolvedPage(systems: pageSystems, titleRows: pageTitleRows))
                    pageSystems = []
                    pageTitleRows = []
                    y = config.margins.top
                }

                // Every staff in the group reports the group's line, so the anchor sequence
                // down the page stays monotonic (issue #41).
                let abcLine = resolvedAbcLine(of: group.staves[0], previous: previousAbcLine)
                previousAbcLine = abcLine
                pageSystems.append(contentsOf: resolveGroup(
                    group, metrics: metrics, topY: y, staffSize: staffSize,
                    staffHeight: staffHeight,
                    graceNoteSpacing: block.graceNoteSpacing, abcLine: abcLine))

                let isLastInBlock = gi == groups.count - 1
                y += metrics.totalHeight + (isLastInBlock ? tuneGap : systemGap)
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

    // MARK: - Staff groups

    /// The vertical shape of one system: where each of its staves sits relative to the
    /// system's top, and how tall the whole thing is.
    private struct GroupMetrics {
        /// Per staff, the space its ledger lines and annotations need above and below it,
        /// and the y of its top staff line relative to the system's top edge.
        let staves: [(extraAbove: Double, extraBelow: Double, staffTopOffset: Double)]
        /// Full height of the group: every staff's extent plus the gaps between them.
        let totalHeight: Double
        /// Width of the widest clef + key + time signature run in the group.  Every staff
        /// starts its first measure there, so their bar lines can align.
        let startWidth: Double
        /// The group's braces and brackets, and the indent they stand in.  Computed here
        /// rather than where they are drawn because the spans decide the spacing as well as
        /// the furniture: a staff a span reaches past is not drawn *and* not tightened.
        let columns: BracketColumns
        /// The space this system's voice labels stand in, left of the braces and brackets.
        /// Empty on every system whose voices print no name.
        let labels: VoiceLabelGutter
    }

    private func groupMetrics(of group: JustifiedSystemGroup,
                              config: SVGRenderConfig) -> GroupMetrics {
        let staffSize = config.staffSize
        let staffHeight = 4.0 * staffSize
        let columns = BracketColumns(grouping: group.grouping, staffCount: group.staves.count,
                                     metadata: metadata, staffSize: staffSize)
        var staves: [(extraAbove: Double, extraBelow: Double, staffTopOffset: Double)] = []
        staves.reserveCapacity(group.staves.count)
        var offset = 0.0
        var startWidth = 0.0
        for (i, staff) in group.staves.enumerated() {
            let (extraAbove, extraBelow) = verticalExtent(of: staff, staffSize: staffSize)
            staves.append((extraAbove, extraBelow, offset + extraAbove))
            offset += extraAbove + staffHeight + extraBelow
            if i < group.staves.count - 1 {
                offset += columns.sharesInnermostSpan(i, i + 1) ? config.spanStaffGap : config.staffGap
            }
            startWidth = max(startWidth, systemStartWidth(for: staff, staffSize: staffSize))
        }
        return GroupMetrics(staves: staves, totalHeight: offset, startWidth: startWidth,
                            columns: columns,
                            labels: VoiceLabelGutter(labels: group.staves.map(\.voiceLabel),
                                                     font: labelFont, staffSize: staffSize))
    }

    /// Places every staff of one system, top to bottom, starting at `topY`.
    private func resolveGroup(_ group: JustifiedSystemGroup, metrics: GroupMetrics,
                              topY: Double, staffSize: Double, staffHeight: Double,
                              graceNoteSpacing: Double,
                              abcLine: Int) -> [ResolvedSystem] {
        // A group of one is an ordinary system: no membership, no group furniture, and the
        // same output the renderer produced before staff groups existed.
        let isGrouped = group.staves.count > 1
        // The foot of the line that joins the staves at the left edge: the bottom staff line
        // of the last staff.
        let last = metrics.staves[metrics.staves.count - 1]
        let groupBottomY = topY + last.staffTopOffset + staffHeight

        // The staves start right of the margin by whatever the group's voice labels and its
        // braces and brackets need, in that order — the labels stand outside the furniture,
        // or they would be printed over it — and nowhere else: a tune with neither reserves
        // nothing and lands on the page the renderer drew before either existed.  The line
        // breaker was handed the same reservation, so the music still ends on the right
        // margin (see `VoiceLabelGutter` and `BracketColumns`).
        let columns = metrics.columns
        let staffLeftX = config.margins.left + metrics.labels.width + columns.indent
        let labelRightX = metrics.labels.rightEdgeX(from: config.margins.left)

        // The plan's spans, placed: a span reaches from the top staff line of its first
        // staff to the bottom staff line of its last, standing in the column its depth was
        // given.  Keyed by first staff, which is the one that draws it.
        let spansByFirstStaff = Dictionary(
            grouping: columns.spans, by: \.staves.lowerBound
        ).mapValues { spans in
            spans.map { span in
                StaffGroup.Span(
                    bracket: span.bracket, staves: span.staves, depth: span.depth,
                    x: columns.spineX(depth: span.depth, staffLeftX: staffLeftX),
                    topY: topY + metrics.staves[span.staves.lowerBound].staffTopOffset,
                    bottomY: topY + metrics.staves[span.staves.upperBound].staffTopOffset
                             + staffHeight)
            }
        }

        return group.staves.enumerated().map { i, staff in
            let (extraAbove, extraBelow, staffTopOffset) = metrics.staves[i]
            // `origin.y` is the top of the staff's own band; `staffOrigin` walks down from
            // there to the top staff line, exactly as in the single-staff case.
            let systemOrigin = Point(x: staffLeftX, y: topY + staffTopOffset - extraAbove)
            let measures = resolveMeasures(
                staff.measures,
                systemOrigin: systemOrigin,
                extraAbove: extraAbove,
                systemStartWidth: metrics.startWidth
            )
            let membership: StaffGroup? = isGrouped ? StaffGroup(
                index: i,
                count: group.staves.count,
                nextStaffTopY: i + 1 < metrics.staves.count
                    ? topY + metrics.staves[i + 1].staffTopOffset
                    : nil,
                bottomY: groupBottomY,
                spans: spansByFirstStaff[i] ?? [],
                // No plan means every boundary continues, as it has since multi-voice
                // systems were introduced; a plan states the ones it wants and the rest
                // stop at their own staff.
                continuesBarlineBelow: i + 1 < group.staves.count
                    && (group.grouping?.barlineJoins.contains(i) ?? true)
            ) : nil
            return ResolvedSystem(
                origin: systemOrigin,
                measures: measures,
                staffOrigin: extraAbove,
                staffSize: staffSize,
                staffHeight: staffHeight,
                graceNoteSpacing: graceNoteSpacing,
                extraAbove: extraAbove,
                extraBelow: extraBelow,
                totalHeight: extraAbove + staffHeight + extraBelow,
                clef: staff.clef,
                keySignature: staff.keySignature,
                meter: staff.meter,
                abcLine: abcLine,
                staffGroup: membership,
                voiceLabel: staff.voiceLabel.map { VoiceLabel(text: $0, x: labelRightX) },
                voiceStemDirections: staff.voiceStemDirections
            )
        }
    }

    // MARK: - Clef width

    /// Returns the total vertical space required to render `block` on a single page,
    /// including its title block, all systems, and inter-system gaps (but not the
    /// trailing gap that follows the last system).
    private func totalHeight(of block: TuneBlock) -> Double {
        let tuneConfig = config.scaled(by: block.scale)
        var h = block.titleBlockHeight
        for (i, group) in block.systemGroups.enumerated() {
            h += groupMetrics(of: group, config: tuneConfig).totalHeight
            if i < block.systemGroups.count - 1 { h += tuneConfig.systemGap }
        }
        return h
    }

    /// Width of the clef + key signature + time signature run that precedes the first
    /// measure of `jsystem`, at the given staff size.
    private func systemStartWidth(for jsystem: JustifiedSystem, staffSize: Double) -> Double {
        let timeSigW = jsystem.meter.map {
            timeSignatureWidth(for: $0, metadata: metadata, staffSize: staffSize)
        } ?? 0
        // When no time signature follows, use noteheadWidth as the trailing gap after the key
        // signature so the space to the first bar line equals one note head.
        let keySigTrailing: Double? = timeSigW > 0 ? nil : {
            metadata.glyphBBoxes["noteheadBlack"].map { $0.width * staffSize }
                ?? staffSize * 1.2
        }()
        let keySigW = jsystem.keySignature.map {
            keySignatureWidth(for: $0, metadata: metadata, staffSize: staffSize,
                              trailingGap: keySigTrailing)
        } ?? 0
        let clefW = clefHeaderWidth(for: jsystem.clef, metadata: metadata, staffSize: staffSize)
        return clefW + keySigW + timeSigW
    }

    /// The 1-based ABC source line of the first measure that contributes content
    /// to `jsystem`, used for scroll-sync anchor metadata (issue #25).
    ///
    /// When `jsystem` has no measure to resolve a line from, falls back to
    /// `previous + 1` rather than a fixed constant, so a system whose own line
    /// can't be determined still reports a position consistent with its place in
    /// the document instead of a bogus jump back to the top (issue #30). A fallback
    /// of `1` only applies to a genuinely first, lineless system — a case that in
    /// practice never arises, since a source with no lines produces no systems at all.
    private func resolvedAbcLine(of jsystem: JustifiedSystem, previous: Int?) -> Int {
        if let line = jsystem.measures.first?.source.measure.source.line {
            return line
        }
        return previous.map { $0 + 1 } ?? 1
    }

    // MARK: - Vertical extent

    private func verticalExtent(of system: JustifiedSystem,
                                staffSize: Double) -> (extraAbove: Double, extraBelow: Double) {
        var maxLedgerAbove = 0
        var maxLedgerBelow = 0
        var hasChordSymbolsOrAnnotations = false
        var verses = 0
        var hasGraceGroups = false

        for jm in system.measures {
            for event in jm.source.measure.events {
                scan(
                    event,
                    maxLedgerAbove: &maxLedgerAbove,
                    maxLedgerBelow: &maxLedgerBelow,
                    hasChordSymbolsOrAnnotations: &hasChordSymbolsOrAnnotations,
                    verses: &verses,
                    hasGraceGroups: &hasGraceGroups
                )
            }
        }

        let s = staffSize
        // Grace note stems always point upward (graceScale=0.6) × 3.5 staff spaces above the
        // notehead. Reserve that height so stems never intrude into the title block zone.
        let graceOvershoot = hasGraceGroups ? 3.5 * s * 0.6 : 0
        let baseAbove = Double(maxLedgerAbove) * s + (hasChordSymbolsOrAnnotations ? s : 0) + graceOvershoot
        // Tempo annotations (from inline Q: events) are placed 1.5 staffSizes above the top
        // staff line; font size is 1.5 staffSizes, so the bounding box extends ~3× above.
        let hasTempoChanges = system.measures.contains { jm in
            jm.source.measure.events.contains { if case .tempoChange = $0 { return true }; return false }
        }
        let extraAbove = hasTempoChanges ? max(baseAbove, s * 3) : baseAbove
        // The verses hang below the ledger lines, so the two are added rather than maxed:
        // a low note and the syllable under it need the space each of them asked for.
        let extraBelow = Double(maxLedgerBelow) * s + LyricBand.height(verses: verses, staffSize: s)
        return (extraAbove, extraBelow)
    }

    private func scan(
        _ event: Event,
        maxLedgerAbove: inout Int,
        maxLedgerBelow: inout Int,
        hasChordSymbolsOrAnnotations: inout Bool,
        verses: inout Int,
        hasGraceGroups: inout Bool
    ) {
        switch event {
        case .note(let n):
            accumulate(pitch: n.pitch, above: &maxLedgerAbove, below: &maxLedgerBelow)
            if n.chordSymbol != nil || !n.annotations.isEmpty { hasChordSymbolsOrAnnotations = true }
            verses = max(verses, n.lyrics.count)
        case .chord(let c):
            for n in c.notes { accumulate(pitch: n.pitch, above: &maxLedgerAbove, below: &maxLedgerBelow) }
            if c.chordSymbol != nil || !c.annotations.isEmpty { hasChordSymbolsOrAnnotations = true }
            verses = max(verses, c.lyrics.count)
        case .tuplet(let t):
            for e in t.events {
                scan(e,
                     maxLedgerAbove: &maxLedgerAbove,
                     maxLedgerBelow: &maxLedgerBelow,
                     hasChordSymbolsOrAnnotations: &hasChordSymbolsOrAnnotations,
                     verses: &verses,
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

            let voices = jm.eventVoiceIndices
            let events: [ResolvedEvent] = zip(jm.eventOffsets, jm.source.measure.events)
                .enumerated().map { i, pair in
                    let (offset, event) = pair
                    return ResolvedEvent(
                        origin: Point(x: measureOrigin.x + offset, y: eventBaseY),
                        kind: ResolvedEventKind(from: event),
                        // Parallel by construction, but a hand-built `SizedMeasure` in a test
                        // can be short; fall back to the staff's own voice rather than trap.
                        voiceIndex: i < voices.count ? voices[i] : 0
                    )
                }

            // A bar line between two measures belongs to both of them: the semantic
            // pass stores the same `BarLine` as the left measure's `closingBar` and
            // the right measure's `openingBar`.  Both resolve to the same x, so only
            // one of the two is kept — the closing one — and the duplicate opening
            // bar is dropped rather than emitted a second time on top of itself.
            //
            // At the start of a system (i == 0) the inherited bar is the *previous
            // system's* closing bar, so it is dropped too, except for explicit
            // section-start markers ([|, [|:, |:, ::), which are conventionally
            // restated at the start of a line.  Anything else would appear as a
            // spurious bar line between the clef/key signature and the first note.
            let openingBar: ResolvedBarLine? = {
                guard let bar = jm.source.measure.openingBar else { return nil }
                guard i > 0 else {
                    switch bar.kind {
                    case .start, .sectionRepeatStart, .repeatStart, .repeatBoth:
                        return ResolvedBarLine(x: measureOrigin.x, kind: bar.kind)
                    default:
                        return nil
                    }
                }
                guard bar != measures[i - 1].source.measure.closingBar else { return nil }
                return ResolvedBarLine(x: measureOrigin.x, kind: bar.kind)
            }()
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
