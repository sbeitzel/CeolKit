import CeolKitModel

/// Pass 4: assigns absolute page coordinates to every system, measure, and event.
///
/// Vertical extent is derived by scanning note pitches (staff positions under each system's clef),
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
    /// Space kept clear above the bottom margin on every page, for a `%%footer` that will be
    /// stamped there once layout is done (issue #192).  Zero in a document with no footer,
    /// which therefore lays out exactly as it did before there was a reservation at all.
    private let bottomReserve: Double

    public init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.init(config: config, metadata: metadata, labelFont: nil)
    }

    init(config: SVGRenderConfig, metadata: BravuraMetadata, labelFont: OpenTypeFont?,
         bottomReserve: Double = 0) {
        self.config = config
        self.metadata = metadata
        self.labelFont = labelFont
        self.bottomReserve = bottomReserve
    }

    /// The lowest y anything laid out on a page of height `pageHeight` may reach: the bottom
    /// margin, raised by the footer band where the document prints one.
    private func floorY(pageHeight: Double) -> Double {
        pageHeight - config.margins.bottom - bottomReserve
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
        // A staff of its own is a group of one, so the same walk that carries an ending over
        // a system break in a multi-voice tune serves here too.
        let endingRuns = EndingBracketBand.runs(
            in: systems.map { JustifiedSystemGroup(staves: [$0]) },
            closeAll: config.closeVariants)
        let openHairpins = DynamicsBand.openAtStart(of: systems.map { JustifiedSystemGroup(staves: [$0]) })
        let lyricStaves = DynamicsBand.staffHasLyrics(in: systems.map { JustifiedSystemGroup(staves: [$0]) })

        for (index, jsystem) in systems.enumerated() {
            let runs = endingRuns[index][0]
            let extent = verticalExtent(of: jsystem, staffSize: config.staffSize,
                                        styles: .standard(staffSize: config.staffSize),
                                        hasEndingBracket: !runs.isEmpty,
                                        dynamicsOverStaff: lyricStaves.contains(0),
                                        openHairpins: openHairpins[index][0])
            let (extraAbove, extraBelow) = (extent.extraAbove, extent.extraBelow)
            let totalHeight = extraAbove + staffHeight + extraBelow

            if !pageSystems.isEmpty && y + totalHeight > floorY(pageHeight: config.pageSize.height) {
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
                clef: jsystem.clef,
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
                abcLine: abcLine,
                endingBrackets: EndingBracketBand.place(
                    runs, over: measures, bandTopY: systemOrigin.y,
                    staffSize: config.staffSize, metadata: metadata),
                annotationFloors: extent.annotationFloors,
                headerKeyChange: jsystem.headerKeyChange
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
    /// cannot accommodate a tune's title block and its first system together, or when a
    /// `%%newpage` in the source demands one (issue #140).
    /// Each tune's title rows are offset from their tune-relative `baselineY` values
    /// by the actual page y-origin at the moment they are placed.
    ///
    /// - Parameter firstPageNumber: what the document's opening page is called, from
    ///   `%%ceolkit:pagenumber`.  Every page is stamped with the number it prints as it is
    ///   closed, because a `%%newpage N` renumbers *and* breaks, and only the walk that
    ///   decides where the pages fall can honour both at once.
    public func layout(_ tuneBlocks: [TuneBlock], firstPageNumber: Int = 1) -> ResolvedLayout {
        layoutDocument(tuneBlocks, firstPageNumber: firstPageNumber).layout
    }

    /// Lays out a sequence of tune blocks and reports where each one landed (issue #152).
    ///
    /// Identical to ``layout(_:firstPageNumber:)`` in everything it produces; it just keeps
    /// the placement map the packing walk builds on its way through instead of dropping it.
    /// Which page a tune starts on is a fact only this walk knows — tunes share pages when
    /// they fit — so a consumer that has to print a table of contents, or answer "turn to
    /// page N", has no way to work it out from the emitted SVG.
    ///
    /// `placements` holds one entry per block, in the order they were handed in.
    public func layoutDocument(_ tuneBlocks: [TuneBlock], firstPageNumber: Int = 1)
        -> (layout: ResolvedLayout, placements: [TunePlacement]) {
        var pages: [ResolvedPage] = []
        var placements: [TunePlacement] = []
        var pageSystems: [ResolvedSystem] = []
        var pageTitleRows: [ResolvedTitleRow] = []
        var y = config.margins.top
        var previousAbcLine: Int?
        var pageNumber = firstPageNumber
        /// The size of the page being built.  A `%%landscape` written at a `%%newpage` moves
        /// it (issue #158), and it stays put until another break says otherwise, so the walk
        /// carries it rather than reading `config.pageSize`: the page a system is being
        /// packed into is not necessarily the size the document opened at, and how much
        /// music a page holds is exactly this height.
        var pageSize = Size(width: config.pageSize.width, height: config.pageSize.height)
        /// The block that put the first thing on the page being built — its title block, or
        /// its first system where a tune spills over from the page before.  Claimed once and
        /// held until the page is flushed, which is what makes it the tune that *opens* the
        /// page rather than the last one to land on it (issue #155).
        var pageOpeningTune: Int?

        /// Closes the page being built and opens an empty one below it.
        func flushPage() {
            pages.append(ResolvedPage(systems: pageSystems, titleRows: pageTitleRows,
                                      pageNumber: pageNumber,
                                      openingTuneIndex: pageOpeningTune,
                                      pageSize: pageSize))
            pageNumber += 1
            pageSystems = []
            pageTitleRows = []
            pageOpeningTune = nil
            y = config.margins.top
        }

        /// Applies whatever `%%newpage` stands in front of system `gi` of `block`.
        ///
        /// A break onto a page nothing has been drawn on yet is not a break: there is
        /// nothing to move.  `%%newpage N` at the head of a document therefore renames the
        /// page it already opens rather than leaving a blank one behind it — which is also
        /// what makes it agree with `%%ceolkit:pagenumber` written in the same place.
        func applyForcedBreak(before gi: Int, of block: TuneBlock) {
            let landing = block.pageBreaks.filter { $0.beforeGroup == gi }
            guard !landing.isEmpty else { return }
            if !pageSystems.isEmpty || !pageTitleRows.isEmpty { flushPage() }
            // Several can land on one system — one in the gap before a tune and another in
            // its header — and the last number written wins, as it does for every directive.
            if let restart = landing.compactMap(\.pageNumber).last { pageNumber = restart }
            // The orientation moves *after* the flush, so the page just closed keeps the size
            // it was packed at and the one now opening takes the new one (issue #158).
            if let size = landing.compactMap(\.pageSize).last { pageSize = size }
        }

        for (blockIndex, block) in tuneBlocks.enumerated() {
            let groups = block.systemGroups
            // Worked out once for the whole tune: an ending can run past a line break, so
            // which measures a bracket covers is not something one system can answer alone.
            // The same table is read by the fits-on-this-page pre-pass below and by the
            // placement that follows it, so the space reserved is the space drawn into.
            let endingRuns = EndingBracketBand.runs(
                in: groups, closeAll: block.closeVariants ?? config.closeVariants)
            // Likewise for the dynamics (#264): a hairpin can run past a line break, and
            // whether a voice's dynamics go over the staff depends on the whole tune's words.
            let openHairpins = DynamicsBand.openAtStart(of: groups)
            let lyricStaves = DynamicsBand.staffHasLyrics(in: groups)
            // The page scale (`%%scale`) sizes this tune's music, text and the gaps derived
            // from staffSize. Page size and margins stay absolute.
            let tuneConfig  = config.scaled(by: block.scale)
            let staffSize   = tuneConfig.staffSize
            let staffHeight = 4.0 * staffSize
            let systemGap   = tuneConfig.systemGap
            let tuneGap     = tuneConfig.tuneGap
            let styles      = block.textStyles ?? .standard(staffSize: staffSize)

            // A `%%newpage` standing before the tune moves its title block too, so it is
            // honoured ahead of everything else this block does.
            applyForcedBreak(before: 0, of: block)

            // If the current page already has content, check whether the entire tune
            // fits in the remaining space. If not, close the current page. Tunes that
            // are taller than a full page are still forced to a fresh page here; the
            // inner system loop below handles the mid-tune page breaks they require.
            if !pageSystems.isEmpty {
                let tuneH = totalHeight(of: block, endingRuns: endingRuns)
                if y + tuneH > floorY(pageHeight: pageSize.height) {
                    flushPage()
                }
            }

            // Everything that can move this tune has now moved it: the `%%newpage` before
            // its title block, and the test above that opens a fresh page for a tune the
            // rest of this one cannot hold.  `y` is therefore the top of the title block,
            // or of the first system where the tune prints no title (issue #152).
            placements.append(TunePlacement(tuneIndex: blockIndex, pageIndex: pages.count,
                                            printedPageNumber: pageNumber, topY: y))

            // Place this tune's title rows, offsetting their tune-relative baselineY by y.
            if !block.titleRows.isEmpty && pageOpeningTune == nil { pageOpeningTune = blockIndex }
            for row in block.titleRows {
                pageTitleRows.append(ResolvedTitleRow(items: row.items.map { $0.offset(by: y) }))
            }
            y += block.titleBlockHeight

            for (gi, group) in groups.enumerated() {
                let metrics = groupMetrics(of: group, config: tuneConfig, styles: styles,
                                           endingRuns: endingRuns[gi],
                                           lyricStaves: lyricStaves,
                                           openHairpins: openHairpins[gi])

                // The tune's own breaks, resolved to the system each stands in front of.
                // Group 0 was dealt with above, before the title block was placed.
                if gi > 0 { applyForcedBreak(before: gi, of: block) }

                // A group breaks to the next page whole: splitting it would separate staves
                // that only mean anything read together.
                if !pageSystems.isEmpty && y + metrics.totalHeight > floorY(pageHeight: pageSize.height) {
                    flushPage()
                }

                // Every staff in the group reports the group's line, so the anchor sequence
                // down the page stays monotonic (issue #41).
                let abcLine = resolvedAbcLine(of: group.staves[0], previous: previousAbcLine)
                previousAbcLine = abcLine
                if pageOpeningTune == nil { pageOpeningTune = blockIndex }
                pageSystems.append(contentsOf: resolveGroup(
                    group, metrics: metrics, topY: y, staffSize: staffSize,
                    staffHeight: staffHeight,
                    graceNoteSpacing: block.graceNoteSpacing,
                    tuneStemDirection: block.stemDirection,
                    straightFlags: block.straightFlags, graceSlurs: block.graceSlurs,
                    abcLine: abcLine,
                    endingRuns: endingRuns[gi]).map {
                        var system = $0
                        system.textStyles = styles
                        return system
                    })

                let isLastInBlock = gi == groups.count - 1
                // The tune's gap follows its words, where it has any, not its last system.
                let after = !isLastInBlock ? systemGap : block.words.isEmpty ? tuneGap : 0
                y += metrics.totalHeight + after
            }

            // The `W:` words, a line at a time below the last system, so a long set of
            // verses carries on over the page like the music does (issue #187).
            if !block.words.isEmpty {
                let words = styles.words
                y += WordsBlock.topGap(words)
                for line in block.words {
                    let pageHasContent = !pageSystems.isEmpty || !pageTitleRows.isEmpty
                    if pageHasContent && y + WordsBlock.lineHeight(words) > floorY(pageHeight: pageSize.height) {
                        flushPage()
                        // A blank line only separates verses; at the top of a page there is
                        // nothing above it to separate from.
                        if line.isEmpty { continue }
                    }
                    if pageOpeningTune == nil { pageOpeningTune = blockIndex }
                    if !line.isEmpty {
                        pageTitleRows.append(ResolvedTitleRow(items: [ResolvedTitleRow.Item(
                            text: line, x: config.margins.left,
                            baselineY: y + words.ascent, anchor: .start, style: words)]))
                    }
                    y += WordsBlock.lineHeight(words)
                }
                y += tuneGap
            }

            // A `%%newpage` written past the tune's last stave — at the foot of its body
            // rather than in the gap below it — puts whatever follows on a fresh page.
            if !groups.isEmpty { applyForcedBreak(before: groups.count, of: block) }
        }

        if !pageSystems.isEmpty || !pageTitleRows.isEmpty {
            flushPage()
        }

        // A block that drew nothing — no title rows, no systems — was recorded against a
        // page the final flush then had no reason to create.  Clamp it onto the last page
        // there is rather than drop it: the map is one entry per block, indexable by tune.
        let lastPage = max(0, pages.count - 1)
        placements = placements.map {
            $0.pageIndex <= lastPage ? $0
                : TunePlacement(tuneIndex: $0.tuneIndex, pageIndex: lastPage,
                                printedPageNumber: $0.printedPageNumber, topY: $0.topY)
        }

        let layout = ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: pages
        )
        return (layout, placements)
    }

    // MARK: - Staff groups

    /// The vertical shape of one system: where each of its staves sits relative to the
    /// system's top, and how tall the whole thing is.
    private struct GroupMetrics {
        /// Per staff, the space its ledger lines and annotations need above and below it,
        /// and the y of its top staff line relative to the system's top edge.
        let staves: [(extraAbove: Double, extraBelow: Double, staffTopOffset: Double,
                      annotationFloors: AnnotationFloors)]
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

    /// - Parameters:
    ///   - lyricStaves: the staves whose voice has lyrics somewhere in the tune.
    ///   - openHairpins: per staff, the hairpins each voice has open as the group begins.
    private func groupMetrics(of group: JustifiedSystemGroup,
                              config: SVGRenderConfig, styles: TextStyles,
                              endingRuns: [[EndingBracketBand.Run]],
                              lyricStaves: Set<Int> = [],
                              openHairpins: [[Int: [DynamicsBand.Hairpin]]] = []) -> GroupMetrics {
        // Parallel to `group.staves` by construction: `EndingBracketBand.runs(in:)` walks
        // the very groups this is being called for, one entry per staff of each.
        let staffSize = config.staffSize
        let staffHeight = 4.0 * staffSize
        let columns = BracketColumns(grouping: group.grouping, staffCount: group.staves.count,
                                     metadata: metadata, staffSize: staffSize)
        var staves: [(extraAbove: Double, extraBelow: Double, staffTopOffset: Double,
                      annotationFloors: AnnotationFloors)] = []
        staves.reserveCapacity(group.staves.count)
        var offset = 0.0
        var startWidth = 0.0
        let barMarks = barMarkSections(of: group)
        for (i, staff) in group.staves.enumerated() {
            let extent = verticalExtent(
                of: staff, staffSize: staffSize, styles: styles,
                hasEndingBracket: !endingRuns[i].isEmpty,
                barMarks: (barMarks, i),
                dynamicsOverStaff: lyricStaves.contains(i),
                openHairpins: i < openHairpins.count ? openHairpins[i] : [:])
            let (extraAbove, extraBelow) = (extent.extraAbove, extent.extraBelow)
            staves.append((extraAbove, extraBelow, offset + extraAbove, extent.annotationFloors))
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

    /// Which staff of `group` draws each mark that stands at a bar line (#264).
    private func barMarkSections(of group: JustifiedSystemGroup) -> BarMarkSections {
        BarMarkSections(
            staves: group.staves.map { $0.measures.map { ($0.source.measure, $0.eventVoiceIndices) } },
            joinsBelow: { i in
                i + 1 < group.staves.count && (group.grouping?.barlineJoins.contains(i) ?? true)
            })
    }

    /// Places every staff of one system, top to bottom, starting at `topY`.
    private func resolveGroup(_ group: JustifiedSystemGroup, metrics: GroupMetrics,
                              topY: Double, staffSize: Double, staffHeight: Double,
                              graceNoteSpacing: Double,
                              tuneStemDirection: StemDirection?,
                              straightFlags: Bool?,
                              graceSlurs: Bool?,
                              abcLine: Int,
                              endingRuns: [[EndingBracketBand.Run]]) -> [ResolvedSystem] {
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

        let barMarks = barMarkSections(of: group)
        return group.staves.enumerated().map { i, staff in
            let (extraAbove, extraBelow, staffTopOffset, annotationFloors) = metrics.staves[i]
            // `origin.y` is the top of the staff's own band; `staffOrigin` walks down from
            // there to the top staff line, exactly as in the single-staff case.
            let systemOrigin = Point(x: staffLeftX, y: topY + staffTopOffset - extraAbove)
            let measures = resolveMeasures(
                staff.measures,
                clef: staff.clef,
                systemOrigin: systemOrigin,
                extraAbove: extraAbove,
                systemStartWidth: metrics.startWidth,
                barMarks: (barMarks, i)
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
                tuneStemDirection: tuneStemDirection,
                straightFlags: straightFlags,
                graceSlurs: graceSlurs,
                extraAbove: extraAbove,
                extraBelow: extraBelow,
                totalHeight: extraAbove + staffHeight + extraBelow,
                clef: staff.clef,
                keySignature: staff.keySignature,
                meter: staff.meter,
                abcLine: abcLine,
                staffGroup: membership,
                voiceLabel: staff.voiceLabel.map { VoiceLabel(text: $0, x: labelRightX) },
                voiceStemDirections: staff.voiceStemDirections,
                endingBrackets: EndingBracketBand.place(
                    endingRuns[i], over: measures, bandTopY: systemOrigin.y,
                    staffSize: staffSize, metadata: metadata),
                annotationFloors: annotationFloors,
                headerKeyChange: staff.headerKeyChange
            )
        }
    }

    // MARK: - Clef width

    /// Returns the total vertical space required to render `block` on a single page,
    /// including its title block, all systems, and inter-system gaps (but not the
    /// trailing gap that follows the last system).
    private func totalHeight(of block: TuneBlock,
                            endingRuns: [[[EndingBracketBand.Run]]]) -> Double {
        let tuneConfig = config.scaled(by: block.scale)
        let styles = block.textStyles ?? .standard(staffSize: tuneConfig.staffSize)
        var h = block.titleBlockHeight
        let openHairpins = DynamicsBand.openAtStart(of: block.systemGroups)
        let lyricStaves = DynamicsBand.staffHasLyrics(in: block.systemGroups)
        for (i, group) in block.systemGroups.enumerated() {
            h += groupMetrics(of: group, config: tuneConfig, styles: styles,
                              endingRuns: endingRuns[i],
                              lyricStaves: lyricStaves, openHairpins: openHairpins[i]).totalHeight
            if i < block.systemGroups.count - 1 { h += tuneConfig.systemGap }
        }
        return h + WordsBlock.height(lines: block.words.count, style: styles.words)
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
        let keySigW = headerKeySignatureWidth(keySignature: jsystem.keySignature,
                                              keyChange: jsystem.headerKeyChange,
                                              clef: jsystem.clef, metadata: metadata,
                                              staffSize: staffSize, trailingGap: keySigTrailing)
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

    /// - Parameter hasEndingBracket: whether a variant-ending bracket is drawn over this
    ///   staff-system.  Its band is added on top of everything else the staff reaches up to,
    ///   rather than maxed against it: the bracket stands above the ledger lines and the
    ///   chord symbols, not among them.
    ///
    /// The chord symbols and annotations are stacked the same way, beyond the ledger lines
    /// and grace stems on their side of the staff, so the floor they stand on is returned
    /// with the extent for the emitter to find them again (issue #171).
    /// - Parameters:
    ///   - dynamicsOverStaff: the staff's voice has lyrics somewhere in the tune, so — on a
    ///     staff of its own — its dynamics go over it (#264).
    ///   - openHairpins: the hairpins each voice of the staff has open as the system begins.
    private func verticalExtent(of system: JustifiedSystem,
                                staffSize: Double,
                                styles: TextStyles,
                                hasEndingBracket: Bool,
                                barMarks: (sections: BarMarkSections, staff: Int)? = nil,
                                dynamicsOverStaff: Bool = false,
                                openHairpins: [Int: [DynamicsBand.Hairpin]] = [:]
    ) -> (extraAbove: Double, extraBelow: Double, annotationFloors: AnnotationFloors) {
        var maxLedgerAbove = 0
        var maxLedgerBelow = 0
        var verses = 0
        var hasGraceGroups = false

        var tupletAbove = 0.0
        var tupletBelow = 0.0
        var marks = MarkReach()
        marks.openHairpins = openHairpins
        // A hairpin running on from the system before is drawn from this one's start.
        for voice in openHairpins.keys {
            let voicing = markVoicings(voice: voice, of: system)
            for (flipped, _) in voicing.options {
                if MarkReach.dynamicsOver(flipped: flipped, shared: voicing.shared,
                                          overStaff: dynamicsOverStaff) {
                    marks.dynamicsAbove = true
                    marks.dynamicsReachAbove = max(marks.dynamicsReachAbove,
                                                   DecorationStack.staffGap * staffSize)
                } else {
                    marks.dynamicsBelow = true
                    marks.dynamicsReachBelow = max(marks.dynamicsReachBelow,
                                                   DecorationStack.staffGap * staffSize)
                }
            }
        }

        var clef = system.clef
        for (m, jm) in system.measures.enumerated() {
            clef = jm.clef ?? clef
            var tupletOf: [Int: Int] = [:]
            for (t, tuplet) in jm.source.tuplets.enumerated() {
                for index in tuplet.eventIndices { tupletOf[index] = t }
            }
            var tupletPositions = [[Int]](repeating: [], count: jm.source.tuplets.count)
            if jm.source.ownsOpeningBar, let bar = jm.source.measure.openingBar {
                marks.scanBar(barMarks.map { $0.sections.openingDecorations(staff: $0.staff,
                                                                            measure: m) }
                                  ?? bar.decorations,
                              staffSize: staffSize, metadata: metadata)
            }
            marks.scanBar(barMarks.map { $0.sections.closingDecorations(staff: $0.staff, measure: m) }
                              ?? jm.source.measure.closingBar.decorations,
                          highest: highestBeforeClosingBar(jm, clef: clef),
                          staffSize: staffSize, metadata: metadata)
            for (index, event) in jm.source.measure.events.enumerated() {
                if case .clefChange(let change) = event { clef = change }
                let voice = index < jm.eventVoiceIndices.count ? jm.eventVoiceIndices[index] : 0
                marks.scan(event, clef: clef, voice: voice,
                           voicing: markVoicings(voice: voice, of: system),
                           dynamicsOverStaff: dynamicsOverStaff,
                           staffSize: staffSize, metadata: metadata)
                if let t = tupletOf[index] {
                    switch event {
                    case .note(let n):  tupletPositions[t].append(clef.staffPosition(of: n.pitch))
                    case .chord(let c): tupletPositions[t] += c.notes.map { clef.staffPosition(of: $0.pitch) }
                    default:            break
                    }
                }
                scan(
                    event,
                    clef: clef,
                    maxLedgerAbove: &maxLedgerAbove,
                    maxLedgerBelow: &maxLedgerBelow,
                    verses: &verses,
                    hasGraceGroups: &hasGraceGroups
                )
            }
            for positions in tupletPositions {
                let reach = tupletNumberReach(positions, staffSize: staffSize)
                tupletAbove = max(tupletAbove, reach.above)
                tupletBelow = max(tupletBelow, reach.below)
            }
        }
        let lines = AnnotationBand.lineCounts(of: system.measures.flatMap(\.source.measure.events))

        let s = staffSize
        // Grace note stems always point upward (graceScale=0.6) × 3.5 staff spaces above the
        // notehead. Reserve that height so stems never intrude into the title block zone.
        let graceOvershoot = hasGraceGroups ? 3.5 * s * 0.6 : 0
        let floor = AnnotationBand.floorRatio * s
        // A tuplet's number stands beyond the ledger lines and stems of its own notes, which
        // is as far as anything on its side reaches; the annotations stack beyond it (#231).
        // The ornaments and fermatas stand clear of their notes' stems and ledger lines
        // already, so they too are maxed with them rather than added (#264).
        let floorAbove = max(Double(maxLedgerAbove) * s + graceOvershoot, tupletAbove, marks.above)
            + (lines.above > 0 ? floor : 0)
        let floorBelow = max(Double(maxLedgerBelow) * s, tupletBelow, marks.below)
            + (lines.below > 0 ? floor : 0)
        let baseAbove = floorAbove + AnnotationBand.height(
            lines: lines.above, metrics: AnnotationBand.aboveMetrics(styles), staffSize: s)
        let hasTempoChanges = system.measures.contains { jm in
            jm.source.measure.events.contains { if case .tempoChange = $0 { return true }; return false }
        }
        // A tempo change stands over the note after it, so it clears everything that note
        // reaches up to: beyond the chord symbols and annotations where the staff has any,
        // otherwise beyond the floor they would stand on (#234).
        //
        // The dynamics stand beyond the chord symbols and annotations on their side, as
        // abcm2ps sets them after its guitar chords, and on one line along the staff
        // (`%%dynalign`) as far out as the notes they pass over need (#264).  A tempo
        // change stands beyond them in turn.
        var aboveEdge = baseAbove
        var dynamicsAbove: Double?
        if marks.dynamicsAbove {
            let inner = max(marks.dynamicsReachAbove, lines.above > 0 ? baseAbove : 0)
            dynamicsAbove = inner + DynamicsBand.centre * s
            aboveEdge = max(baseAbove, inner + DynamicsBand.height * s)
        }
        var tempoFloor = lines.above > 0 ? baseAbove : floorAbove + floor
        if marks.dynamicsAbove { tempoFloor = max(tempoFloor, aboveEdge) }
        let tempoBaseline = tempoFloor + AnnotationBand.padRatio * s + styles.tempoChange.descent
        var extraAbove = hasTempoChanges
            ? max(aboveEdge, tempoBaseline + styles.tempoChange.ascent) : aboveEdge
        if hasEndingBracket { extraAbove += EndingBracketBand.height(staffSize: s) }
        // The verses hang below the ledger lines and the annotations, so the three are added
        // rather than maxed: a low note and what is written under it need the space each of
        // them asked for.
        // The dynamics come between the annotations and the verses.
        var belowEdge = floorBelow
            + AnnotationBand.height(lines: lines.below, metrics: AnnotationBand.belowMetrics(styles),
                                    staffSize: s)
        var dynamicsBelow: Double?
        if marks.dynamicsBelow {
            let inner = max(marks.dynamicsReachBelow, lines.below > 0 ? belowEdge : 0)
            dynamicsBelow = inner + DynamicsBand.centre * s
            belowEdge = max(belowEdge, inner + DynamicsBand.height * s)
        }
        let extraBelow = belowEdge + LyricBand.height(verses: verses, style: styles.vocal)
        return (extraAbove, extraBelow,
                AnnotationFloors(above: floorAbove, below: floorBelow,
                                 tempoBaseline: hasTempoChanges ? tempoBaseline : nil,
                                 dynamicsAbove: dynamicsAbove, dynamicsBelow: dynamicsBelow))
    }

    /// The highest head among the last notes of each part of `measure`, which a breath mark
    /// on its closing bar line stands clear of.  `clef` is the one the bar opens in.
    private func highestBeforeClosingBar(_ measure: JustifiedMeasure, clef: ClefSpec) -> Int? {
        var clef = clef
        var last: [Int: Int] = [:]
        for (index, event) in measure.source.measure.events.enumerated() {
            if case .clefChange(let change) = event { clef = change }
            let voice = index < measure.eventVoiceIndices.count ? measure.eventVoiceIndices[index] : 0
            switch event {
            case .note(let n):  last[voice] = clef.staffPosition(of: n.pitch)
            case .chord(let c): last[voice] = c.notes.map { clef.staffPosition(of: $0.pitch) }.max()
            case .rest:         last[voice] = nil
            default:            break
            }
        }
        return last.values.max()
    }

    /// How far beyond the staff a tuplet's number reaches, on the side the emitter sets it:
    /// the side its stems go, decided as an unforced beam group decides it, and beyond a
    /// stem of full length (3½ spaces) from the outermost note.  Notes without a pitch — a
    /// tuplet of rests — keep the number just clear of the staff, above it.
    private func tupletNumberReach(_ positions: [Int],
                                   staffSize s: Double) -> (above: Double, below: Double) {
        let number = 0.5 * s + 1.3 * s
        guard let low = positions.min(), let high = positions.max() else {
            return (number, 0)
        }
        let middleLine = 4
        if low + high - 2 * middleLine <= 0 {
            let tip = Double(high + 7 - 8) / 2 * s
            return (max(0, tip) + number, 0)
        } else {
            let tip = Double(-(low - 7)) / 2 * s
            return (0, max(0, tip) + number)
        }
    }

    /// How voice `voice` of `system`'s staff stems and sets its marks, as the possibilities
    /// to reserve room for — the emitter's rule: on a shared staff the part stemmed down
    /// sets them under the staff.  A middle voice that states no direction follows the
    /// tune's, which this pass is not told, so it is given room on both sides.
    private func markVoicings(voice: Int, of system: JustifiedSystem) -> MarkReach.Voicing {
        let count = system.voiceStemDirections.count
        let own = voice < count ? system.voiceStemDirections[voice] : .auto
        guard count > 1 else { return .init(shared: false, options: [(false, own)]) }
        switch own {
        case .down: return .init(shared: true, options: [(true, .down)])
        case .up:   return .init(shared: true, options: [(false, .up)])
        case .auto:
            if voice == 0 { return .init(shared: true, options: [(false, .up)]) }
            if voice == count - 1 { return .init(shared: true, options: [(true, .down)]) }
            return .init(shared: true, options: [(false, .up), (true, .down)])
        }
    }

    /// How far beyond the staff the marks ``DecorationStack`` places on notes reach, by
    /// the same plan the emitter draws them from.  The stem is taken to end where an
    /// unbeamed one would, which a beam a lower note drags further can exceed.
    private struct MarkReach {
        struct Voicing {
            let shared: Bool
            let options: [(flipped: Bool, stem: StemDirection)]
        }

        var above = 0.0
        var below = 0.0
        /// The top of a grace group just scanned, for the note after it.
        private var graceTopY: Double?
        /// How far the highest column so far reaches with its marks, and whether an
        /// extended trill runs over the system: the line clears every column it passes.
        private var highestColumn = 0.0
        private var hasExtendedTrill = false

        /// Whether the staff's dynamics band is wanted over it and under it, and how far
        /// out the notes it passes over reach on that side (#264): it stands beyond them.
        var dynamicsAbove = false
        var dynamicsBelow = false
        var dynamicsReachAbove = 0.0
        var dynamicsReachBelow = 0.0
        /// The hairpins each voice has open.
        var openHairpins: [Int: [DynamicsBand.Hairpin]] = [:]

        /// A voice that sets its dynamics over the staff: abcm2ps's `up_p`.  On a shared
        /// staff every part but the one stemmed down; on a staff of its own, a voice with
        /// lyrics.
        static func dynamicsOver(flipped: Bool, shared: Bool, overStaff: Bool) -> Bool {
            shared ? !flipped : overStaff
        }

        /// The marks written on a bar line: the segno and coda over it, the words under it,
        /// and a pause mark in front of it (#264).
        mutating func scanBar(_ decorations: [Decoration], highest: Int? = nil,
                              staffSize s: Double, metadata: BravuraMetadata) {
            guard !decorations.isEmpty else { return }
            let plan = DecorationStack.planBar(decorations, metadata: metadata)
            if let top = plan.outerAbove { above = max(above, -top * s) }
            if let bottom = plan.outerBelow { below = max(below, (bottom - 4) * s) }
            scanPauses(decorations, highest: highest, staffSize: s, metadata: metadata)
        }

        /// The breath, caesura and phrase marks, which stand over the top line between two
        /// notes rather than on either.
        mutating func scanPauses(_ decorations: [Decoration], highest: Int? = nil,
                                 staffSize s: Double, metadata: BravuraMetadata) {
            for pause in decorations.compactMap(DecorationStack.pause(for:))
                .map({ DecorationStack.raised($0, overStaffPosition: highest) }) {
                above = max(above, DecorationStack.reachAbove(of: pause, metadata: metadata) * s)
            }
        }

        mutating func scan(_ event: Event, clef: ClefSpec, voice: Int, voicing: Voicing,
                           dynamicsOverStaff: Bool,
                           staffSize s: Double, metadata: BravuraMetadata) {
            switch event {
            case .note(let n):
                scanPauses(n.decorations, highest: clef.staffPosition(of: n.pitch),
                           staffSize: s, metadata: metadata)
            case .chord(let c):
                scanPauses(c.decorations + c.notes.flatMap(\.decorations),
                           highest: c.notes.map { clef.staffPosition(of: $0.pitch) }.max(),
                           staffSize: s, metadata: metadata)
            case .rest(let r):  scanPauses(r.decorations, staffSize: s, metadata: metadata)
            default:            break
            }
            let positions: [Int]
            let decorations: [Decoration]
            switch event {
            case .note(let n):
                positions = [clef.staffPosition(of: n.pitch)]
                decorations = n.decorations
            case .chord(let c):
                positions = c.notes.map { clef.staffPosition(of: $0.pitch) }
                decorations = c.decorations + c.notes.flatMap(\.decorations)
            case .tuplet(let t):
                for inner in t.events {
                    scan(inner, clef: clef, voice: voice, voicing: voicing,
                         dynamicsOverStaff: dynamicsOverStaff, staffSize: s, metadata: metadata)
                }
                return
            case .grace(let g):
                // A grace stem stands 3.5 spaces at grace scale over its head.
                let high = g.notes.map { clef.staffPosition(of: $0.pitch) }.max()
                graceTopY = high.map { Double(8 - $0) / 2 - 3.5 * 0.6 }
                return
            case .rest(let r):
                // A rest can carry a dynamic or a hairpin's end, just outside the staff.
                let inBand = DynamicsBand.touches(r.decorations) || !(openHairpins[voice] ?? []).isEmpty
                DynamicsBand.apply(r.decorations, to: &openHairpins[voice, default: []])
                guard inBand else { return }
                for (flipped, _) in voicing.options {
                    if Self.dynamicsOver(flipped: flipped, shared: voicing.shared,
                                         overStaff: dynamicsOverStaff) {
                        dynamicsAbove = true
                        dynamicsReachAbove = max(dynamicsReachAbove, DecorationStack.staffGap * s)
                    } else {
                        dynamicsBelow = true
                        dynamicsReachBelow = max(dynamicsReachBelow, DecorationStack.staffGap * s)
                    }
                }
                return
            default:
                return
            }
            defer { graceTopY = nil }
            guard let low = positions.min(), let high = positions.max() else { return }
            let headYs = positions.map { Double(8 - $0) / 2 }
            let inBand = DynamicsBand.touches(decorations) || !(openHairpins[voice] ?? []).isEmpty
            DynamicsBand.apply(decorations, to: &openHairpins[voice, default: []])

            for (flipped, direction) in voicing.options {
                let stemUp: Bool
                switch direction {
                case .up:   stemUp = true
                case .down: stemUp = false
                case .auto: stemUp = (low + high) / 2 <= 4
                }
                let tip = stemUp ? Double(8 - high) / 2 - 3.5 : Double(8 - low) / 2 + 3.5
                let column = DecorationStack.Column(
                    headYs: headYs, stemUp: stemUp, stemTipY: tip, graceTopY: graceTopY,
                    shared: voicing.shared, flipped: flipped)
                let plan = DecorationStack.plan(decorations, column: column, metadata: metadata)
                if let top = plan.outerAbove { above = max(above, -top * s) }
                if let bottom = plan.outerBelow { below = max(below, (bottom - 4) * s) }
                if !flipped { highestColumn = max(highestColumn, -plan.nextAbove * s) }
                if inBand {
                    if Self.dynamicsOver(flipped: flipped, shared: voicing.shared,
                                         overStaff: dynamicsOverStaff) {
                        dynamicsAbove = true
                        dynamicsReachAbove = max(dynamicsReachAbove, -plan.nextAbove * s)
                    } else {
                        dynamicsBelow = true
                        dynamicsReachBelow = max(dynamicsReachBelow, (plan.nextBelow - 4) * s)
                    }
                }
            }

            if decorations.contains(.trillStart) || decorations.contains(.trillEnd) {
                hasExtendedTrill = true
            }
            if hasExtendedTrill {
                let wiggle = metadata.glyphBBoxes[SMuFLGlyph.wiggleTrill.rawValue]
                let height = ((wiggle?.neY ?? 0.836) - (wiggle?.swY ?? 0.392)) * s
                above = max(above, highestColumn + height)
            }
        }
    }

    private func scan(
        _ event: Event,
        clef: ClefSpec,
        maxLedgerAbove: inout Int,
        maxLedgerBelow: inout Int,
        verses: inout Int,
        hasGraceGroups: inout Bool
    ) {
        switch event {
        case .note(let n):
            accumulate(pitch: n.pitch, clef: clef, above: &maxLedgerAbove, below: &maxLedgerBelow)
            verses = max(verses, n.lyrics.count)
        case .chord(let c):
            for n in c.notes { accumulate(pitch: n.pitch, clef: clef, above: &maxLedgerAbove, below: &maxLedgerBelow) }
            verses = max(verses, c.lyrics.count)
        case .tuplet(let t):
            for e in t.events {
                scan(e,
                     clef: clef,
                     maxLedgerAbove: &maxLedgerAbove,
                     maxLedgerBelow: &maxLedgerBelow,
                     verses: &verses,
                     hasGraceGroups: &hasGraceGroups)
            }
        case .grace(let g):
            hasGraceGroups = true
            for n in g.notes { accumulate(pitch: n.pitch, clef: clef, above: &maxLedgerAbove, below: &maxLedgerBelow) }
        default:
            break
        }
    }

    private func accumulate(pitch: Pitch, clef: ClefSpec, above: inout Int, below: inout Int) {
        let (a, b) = ledgerLines(for: pitch, clef: clef)
        above = max(above, a)
        below = max(below, b)
    }

    /// Returns the number of ledger lines required above and below a staff carrying `clef`.
    ///
    /// The bottom staff line is position 0 and the top line position 8, whatever the clef;
    /// the clef says which pitch each names.  On a treble staff a note on position 10 (A5)
    /// sits on the first ledger line above, and on a bass staff the same is true of C4.
    private func ledgerLines(for pitch: Pitch, clef: ClefSpec) -> (above: Int, below: Int) {
        let staffPos = clef.staffPosition(of: pitch)
        let above = max(0, (staffPos - 8) / 2)
        let below = max(0, (-staffPos) / 2)
        return (above, below)
    }

    // MARK: - Horizontal layout

    /// - Parameter clef: the clef the staff head draws, which the system's first measure is
    ///   in unless a clef change says otherwise.
    private func resolveMeasures(
        _ measures: [JustifiedMeasure],
        clef systemClef: ClefSpec,
        systemOrigin: Point,
        extraAbove: Double,
        systemStartWidth: Double,
        barMarks: (sections: BarMarkSections, staff: Int)? = nil
    ) -> [ResolvedMeasure] {
        var resolved: [ResolvedMeasure] = []
        var x = systemOrigin.x
        // The clef in force, event by event, so every notehead is placed on the clef it was
        // written against (issue #223).
        var clef = systemClef

        for (i, jm) in measures.enumerated() {
            let measureX = i == 0 ? x + systemStartWidth : x
            let measureOrigin = Point(x: measureX, y: systemOrigin.y)
            let eventBaseY = systemOrigin.y + extraAbove

            let voices = jm.eventVoiceIndices
            clef = jm.clef ?? clef
            // A tuplet's notes were spaced for how long they sound; from here on their
            // durations only choose noteheads, flags and beams, which show what was written.
            var tupletOf: [Int: TupletSpan] = [:]
            for tuplet in jm.source.tuplets {
                for index in tuplet.eventIndices { tupletOf[index] = tuplet }
            }
            let events: [ResolvedEvent] = zip(jm.eventOffsets, jm.source.measure.events)
                .enumerated().map { i, pair in
                    let (offset, event) = pair
                    if case .clefChange(let change) = event { clef = change }
                    return ResolvedEvent(
                        origin: Point(x: measureOrigin.x + offset, y: eventBaseY),
                        kind: ResolvedEventKind(from: tupletOf[i].map {
                            TupletExpansion.written(event, in: $0)
                        } ?? event),
                        // Parallel by construction, but a hand-built `SizedMeasure` in a test
                        // can be short; fall back to the staff's own voice rather than trap.
                        voiceIndex: i < voices.count ? voices[i] : 0,
                        clef: clef
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
            //
            // A repeat sign that falls on a system break is split across it, as abcm2ps
            // and engraving convention both do it (issue #197): the half that looks back
            // closes the system, the half that looks forward opens the next one.  So `::`
            // restated at the start of a line keeps only its start-repeat half...
            //
            // None of this applies to a bar written in its own right — `:|` ending one line
            // and `::` opening the next, or `| |` part way through one.  Nothing was split or
            // shared: it is a second bar, drawn whole, as written, wherever it falls (issue
            // #212).  The sizer has said which it is, and kept the room it needs clear of
            // whatever stands before it: the lead.
            func openingMarks(_ bar: BarLine) -> [Decoration] {
                barMarks.map { $0.sections.openingDecorations(staff: $0.staff, measure: i) }
                    ?? bar.decorations
            }
            let openingBar: ResolvedBarLine? = {
                guard let bar = jm.source.measure.openingBar else { return nil }
                if jm.source.ownsOpeningBar {
                    return ResolvedBarLine(x: measureOrigin.x + jm.source.openingBarLead,
                                           kind: bar.kind, decorations: openingMarks(bar))
                }
                guard i > 0 else {
                    switch bar.kind {
                    case .start, .sectionRepeatStart, .repeatStart:
                        return ResolvedBarLine(x: measureOrigin.x, kind: bar.kind)
                    case .repeatBoth:
                        return ResolvedBarLine(x: measureOrigin.x, kind: .repeatStart)
                    default:
                        return nil
                    }
                }
                guard bar != measures[i - 1].source.measure.closingBar else { return nil }
                return ResolvedBarLine(x: measureOrigin.x, kind: bar.kind,
                                       decorations: openingMarks(bar))
            }()
            // ...and at the end of a system a start-repeat draws as a plain bar line, and
            // `::` as its end-repeat half.  Drawn whole, either one's dots — and the thick
            // line of a `|:` — would land past the end of the staff.
            let closingKind: BarLineKind = {
                let kind = jm.source.measure.closingBar.kind
                guard i == measures.count - 1 else { return kind }
                switch kind {
                case .repeatStart, .sectionRepeatStart: return .single
                case .repeatBoth:                       return .repeatEnd
                default:                                return kind
                }
            }()
            let closingBar = ResolvedBarLine(
                x: measureOrigin.x + jm.finalWidth,
                kind: closingKind,
                decorations: barMarks.map { $0.sections.closingDecorations(staff: $0.staff,
                                                                           measure: i) }
                    ?? jm.source.measure.closingBar.decorations,
                drawsPausesBefore: barMarks.map {
                    $0.sections.drawsPausesAtBarLine.indices.contains($0.staff)
                        ? $0.sections.drawsPausesAtBarLine[$0.staff] : true
                } ?? true
            )

            resolved.append(ResolvedMeasure(
                origin: measureOrigin,
                width: jm.finalWidth,
                events: events,
                openingBar: openingBar,
                closingBar: closingBar,
                unitNoteLength: jm.source.unitNoteLength,
                meter: jm.source.measure.meter,
                keyChange: jm.keyChange,
                trailingClef: jm.trailingClef,
                tuplets: jm.source.tuplets
            ))

            x = measureOrigin.x + jm.finalWidth
        }

        return resolved
    }
}
