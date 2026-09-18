import CeolKitModel
import CeolKitRenderer
import Foundation

/// Entry point for the SVG renderer.
///
/// Initialise once with a `SVGRenderConfig` and call `render(_:)` for each `Score`.
public struct SVGRenderer: CeolKitRenderer {
    public typealias Output = [String]

    public let config: SVGRenderConfig

    public init(config: SVGRenderConfig = SVGRenderConfig()) {
        self.config = config
    }

    /// Returns one SVG string per page.
    public func render(_ score: Score) throws -> [String] {
        var diagnostics: [Diagnostic] = []
        return try render(score, diagnostics: &diagnostics)
    }

    /// Returns one SVG string per page, appending anything the *renderer* had to complain
    /// about to `diagnostics`.
    ///
    /// Separate from `render(_:)` because rendering can discover problems parsing cannot:
    /// laying two voices out as one system means the voices have to agree about where the
    /// bar lines fall, and only the renderer is in a position to notice that they do not
    /// (see `VoiceAligner`).  `Score.diagnostics` is already sealed by then, so the caller
    /// that wants to report both concatenates them.
    public func render(_ score: Score, diagnostics: inout [Diagnostic]) throws -> [String] {
        try renderDocument(score, diagnostics: &diagnostics).pages
    }

    /// Returns the pages, the layout they were emitted from, and where each tune landed
    /// (issue #152).
    ///
    /// Same rendering as ``render(_:)``, which throws the last two away.  A multi-tune score
    /// packs tunes onto shared pages, so which page a tune starts on is something only the
    /// layout knows — and nothing in the emitted SVG says.  A caller building a table of
    /// contents, or reporting where a tune came out, reads it from ``RenderedDocument``.
    public func renderDocument(_ score: Score) throws -> RenderedDocument {
        var diagnostics: [Diagnostic] = []
        return try renderDocument(score, diagnostics: &diagnostics)
    }

    /// Returns the pages, the layout, and the tune placements, appending anything the
    /// *renderer* had to complain about to `diagnostics` — see ``render(_:diagnostics:)``.
    public func renderDocument(_ score: Score,
                               diagnostics: inout [Diagnostic]) throws -> RenderedDocument {
        let metadata = try BravuraMetadata.load()

        // Apply score-level directives that affect the whole document.
        // File-preamble directives are promoted to the first tune by the parser.
        let effectiveConfig = applyingScoreDirectives(score)

        // The face voice labels are measured in, read once and only when a voice has a label
        // to measure: parsing the bundled faces is the most expensive thing this renderer
        // does, and a score that names no voice needs none of it.  `nil` where the resource
        // could not be read — `VoiceLabelGutter` estimates from there, on both sides of the
        // reservation, so the labels still land in the space kept for them.
        let labelFont = score.tunes.contains(where: \.hasVoiceLabels)
            ? OutlineFontSet.textFace() : nil

        let breaker   = LineBreaker(overflowTolerance: effectiveConfig.lineOverflowTolerance)
        let justifier = Justifier(maxStretch: effectiveConfig.maxSystemStretch)
        let engine    = VerticalLayoutEngine(config: effectiveConfig, metadata: metadata,
                                             labelFont: labelFont)

        // The line width one page size gives.  A function rather than the single number it
        // used to be: `%%landscape` at a `%%newpage` turns the page part-way through the
        // document (issue #158), and a system is broken and justified to the width of the
        // page it lands on, so this is asked once per *region* rather than once per document.
        func usableWidth(on pageSize: Size) -> Double {
            pageSize.width - effectiveConfig.margins.left - effectiveConfig.margins.right
        }

        // File-preamble directives are promoted to the first tune by the parser.
        // Build a file-level WriteFieldsConfig from those file-global-scoped directives
        // so each tune can start from that baseline and layer its own on top.
        let fileWriteFields: WriteFieldsConfig = {
            var wf = WriteFieldsConfig.default
            for scope in score.tunes.first?.directives ?? [] {
                guard case .fileGlobal = scope.scope else { continue }
                wf.apply(scope.directive)
            }
            return wf
        }()

        // The four layout values `%%ceolkit:*` can move, resolved from the file-global
        // directives alone: a preamble value governs the document, so this is the baseline
        // every tune starts from.  It is *not* what any tune ends up with — see below.
        let fileLayout: LayoutDirectives = {
            var resolved = LayoutDirectives(config: effectiveConfig)
            for scope in score.tunes.first?.directives ?? [] {
                guard case .fileGlobal = scope.scope else { continue }
                resolved.apply(scope.directive)
            }
            return resolved
        }()

        var tuneBlocks: [TuneBlock] = []

        // The size of the page the document is currently on, threaded through the tunes in
        // order: a page size persists until a `%%landscape` at a `%%newpage` changes it, so a
        // tune that states nothing opens on whatever the tune before it left in force.
        var runningPageSize = Size(width: effectiveConfig.pageSize.width,
                                   height: effectiveConfig.pageSize.height)

        for tune in score.tunes {
            // Where this tune's pages change size, and what they change to.  Resolved before
            // anything is packed because a page size decides the *width* the music is broken
            // to as well as the height it is packed into.
            let pageSizes = Self.pageSizePlan(for: tune, inherited: runningPageSize,
                                              portrait: config.pageSize)
            runningPageSize = pageSizes.closing
            // Resolved per tune, from the file baseline rather than from the tune before it:
            // a tune header applies to its own tune (ABC v2.2 §4.23), so a `%%ceolkit:scale`
            // in tune 1's header must not still be in force in tune 2 (issue #153).
            let layout = fileLayout.layering(tune)
            // The music scales; the page does not. Sizing and header widths are therefore
            // derived from a per-tune staff size, while `usableWidth` stays absolute.
            var tuneConfig = effectiveConfig.scaled(by: layout.scale)
            // A ratio within the grace group, not a size derived from the staff, so it is
            // set after `scaled(by:)` and never multiplied by the scale factor.
            tuneConfig.graceNoteSpacing = layout.graceNoteSpacing
            let sizer = MeasureSizer(config: tuneConfig, metadata: metadata)

            // §11.1: a `%%score` / `%%staves` plan decides which voices are printed and in
            // what order, and one written in the tune body resets that part-way through.
            // The staff count is therefore not a property of the tune, so the whole
            // align → size → break block below runs once per *plan region* — a maximal run
            // of staves under one plan — and the systems are concatenated.  A region
            // boundary is always a system break; a staff plan cannot change mid-system.
            var groups: [SystemGroup] = []
            var headerWidths: [Double] = []
            // The tune stave each system came from, parallel to `groups`.  `%%newpage` is
            // written against a stave — one source line of music — and pagination happens in
            // systems, so this is where the two are reconciled: it is the last point that
            // still knows which systems the packer made out of which stave.
            var staveOfGroup: [Int] = []
            // The key each voice is standing in, threaded across the regions: a `%%score` in
            // the body cuts the tune but does not reset it, so the region after one opens in
            // whatever key the music before it reached (#134).  Empty until a body `K:` moves
            // a voice, which leaves the tune's own key standing for everything else.
            var runningKeys: [VoiceId: KeySignature] = [:]
            // The line width each system was broken to, parallel to `groups`: the justifier
            // has to spend exactly what the breaker charged, and across an orientation change
            // that is not one number for the tune (issue #158).
            var usableWidthOfGroup: [Double] = []

            for region in PlanRegions.segment(tune, alsoCuttingAt: pageSizes.boundaries) {
                // The page this region's systems land on — a region never spans an
                // orientation change, because every stave one lands on cuts a region.
                let usableWidth = usableWidth(on: pageSizes.size(atStave: region.staves.lowerBound))
                let selection = VoiceSelector.select(from: region.voices, plan: region.plan,
                                                     into: &diagnostics)
                let printedVoices = selection.voices
                guard !printedVoices.isEmpty else { continue }

                // §7.3: a voice states its own `K:` where it needs one, and the tune's stands
                // in where it does not.  This is the key the voice *opens* this region in,
                // not one it holds throughout: a body `K:` moves it, and the staff heads
                // after that draw the new one (#134), which the column walk below resolves.
                // The unit note length is not resolved here either — an `L:` moves it part
                // way through a voice, so it is the measure that carries it (issue #122).
                let voiceKeys = printedVoices.map { runningKeys[$0.id] ?? tune.effectiveKey(for: $0) }

                // Bring the voices into agreement about how much music each source line
                // holds, so the break points chosen below are legal for every one of them.
                // Voices that disagree are padded and warned about rather than laid out
                // sequentially.
                let alignedStaves = VoiceAligner.align(printedVoices, into: &diagnostics)

                // Flatten the aligned staves into one measure column per bar, carrying the
                // stave boundaries as .hard breaks: the semantic pass makes one Staff per
                // source line-break, so the last column of every non-final stave forces a
                // system break.  The region's own final stave needs none — the region ends
                // there, and the next one starts a new system anyway.
                //
                // §11.1 `( … )`: a staff may carry more than one voice, and those are merged
                // onto a common onset grid here — before sizing, because interleaved onsets
                // need more columns than either voice alone and neither the breaker's nor
                // the justifier's `max` across staves can invent one.
                let voicesByStaff = selection.voicesByStaff
                var breaks: [ScoreLineBreak?] = []
                var columnsPerStaff = [[SizedMeasure]](repeating: [], count: voicesByStaff.count)
                // The same columns as they are drawn when one opens a system: the change moves
                // up into the staff head there, so the bar reserves no space for it (#134).
                // Only a column carrying a `K:` differs, and only that one is sized twice.
                var startColumnsPerStaff = [[SizedMeasure]](repeating: [], count: voicesByStaff.count)
                // The key each staff is standing in, so a `K:` part way through the tune is
                // drawn as the change it is — the naturals cancelling the signature being
                // left behind, then the new one (#129).  It starts at what the staff's head
                // draws, which is its lead voice's key, and moves with that voice's own
                // `K:`: one staff carries one signature, and the lead is the voice whose
                // clef and key the head already reads (§7.3).
                var staffKeys: [KeySignature?] = voicesByStaff.map { voiceKeys[$0[0]] }
                // That running value, kept rather than discarded: it is the signature the head
                // of a system opening at this column has to draw, and it is knowable here —
                // before anything is packed — because it depends only on the columns before it
                // and not on how they were broken (#134).
                var columnKeysPerStaff = [[KeySignature?]](repeating: [], count: voicesByStaff.count)
                for (si, stave) in alignedStaves.enumerated() {
                    let isLastStave = si == alignedStaves.count - 1
                    for column in 0..<stave.measureCount {
                        breaks.append(!isLastStave && column == stave.measureCount - 1 ? .hard : nil)
                        for (staffIndex, members) in voicesByStaff.enumerated() {
                            let lead = members[0]
                            var keyChange: KeyChange? = nil
                            if let newKey = stave.measures[lead][column].key {
                                keyChange = KeyChange(from: staffKeys[staffIndex], to: newKey,
                                                      clef: printedVoices[lead].properties.clef)
                                staffKeys[staffIndex] = newKey
                            }
                            columnKeysPerStaff[staffIndex].append(staffKeys[staffIndex])
                            let parts = members.enumerated().map { position, voice in
                                MeasureSizer.SharedVoice(
                                    measure: stave.measures[voice][column],
                                    voiceIndex: position,
                                    isPadding: stave.isPadding(voice: voice, column: column))
                            }
                            let sized = sizer.size(sharedStaff: parts, keyChange: keyChange)
                            columnsPerStaff[staffIndex].append(sized)
                            startColumnsPerStaff[staffIndex].append(
                                keyChange == nil ? sized : sizer.size(sharedStaff: parts))
                        }
                    }
                }
                guard !breaks.isEmpty else { continue }
                // Hand the keys this region ended in to the next one.  A staff carries one
                // signature, so every voice drawn on it leaves in the key its lead does.
                for (staffIndex, members) in voicesByStaff.enumerated() {
                    guard let key = staffKeys[staffIndex] else { continue }
                    for voice in members { runningKeys[printedVoices[voice].id] = key }
                }

                // Everything below draws one staff at a time, and a shared staff draws the
                // clef, key and name of the voice written at the top of it — as an engraver
                // does, and as `V:` order decides.
                let staffLead = voicesByStaff.map { $0[0] }

                // A time signature is drawn once, on the tune's very first system.  A later
                // region opens a fresh set of staves, but it is still the same tune, and a
                // meter no more repeats at a staff-plan change than it does at a line break.
                let isOpeningRegion = groups.isEmpty
                let regionMeter = isOpeningRegion ? tune.meter : nil

                // §4.1: `name=` labels the voice on the first system it appears on and
                // `sname=` on every later one.  A region after the opening one is not the
                // first system of anything — the voice has already been named — so it takes
                // the subname throughout, exactly as a line break within a region does.
                let firstLabels = staffLead.map {
                    isOpeningRegion ? printedVoices[$0].properties.name
                                    : printedVoices[$0].properties.subname
                }
                let laterLabels = staffLead.map { printedVoices[$0].properties.subname }

                // The clef, key and label are the staff lead's; the stem directions are
                // every tenant's, in staff order.  A shared staff opposes its voices' stems
                // rather than reading each note's pitch (issue #77), and it is the voices
                // that were *not* drawn first whose own `stem=` would otherwise be lost.
                let voiceLines = staffLead.enumerated().map { staffIndex, voice in
                    LineBreaker.VoiceLine(measures: columnsPerStaff[staffIndex],
                                          clef: printedVoices[voice].properties.clef,
                                          keySignature: voiceKeys[voice],
                                          meter: regionMeter,
                                          firstSystemLabel: firstLabels[staffIndex],
                                          laterSystemLabel: laterLabels[staffIndex],
                                          voiceStemDirections: voicesByStaff[staffIndex].map {
                                              printedVoices[$0].properties.stemDirection
                                          },
                                          systemStartMeasures: startColumnsPerStaff[staffIndex],
                                          columnKeys: columnKeysPerStaff[staffIndex])
                }
                // Space for the region's braces and brackets, reserved before anything is
                // packed into the line.  It is added to the header widths rather than taken
                // off `usableWidth` because that is the one number both the breaker and the
                // justifier already subtract, and `VerticalLayoutEngine` spends exactly the
                // same amount moving the staves right (see `BracketColumns`).
                let indent = BracketColumns(grouping: selection.grouping,
                                            staffCount: voicesByStaff.count,
                                            metadata: metadata,
                                            staffSize: tuneConfig.staffSize).indent

                // Space for the voice names, outside the furniture.  Two widths, because the
                // labels differ: the first system carries the full names and later ones the
                // subnames, so a voice named "Soprano" with `snm="S"` indents its opening
                // system further than the rest — which is what an engraver draws, and what
                // the separate first/later header widths below already express.
                let openingGutter = VoiceLabelGutter(labels: firstLabels, font: labelFont,
                                                     staffSize: tuneConfig.staffSize).width
                let laterGutter = VoiceLabelGutter(labels: laterLabels, font: labelFont,
                                                   staffSize: tuneConfig.staffSize).width

                // The header width of one system: the max across the group, because its staves
                // have to start at the same x even when one voice's clef or key signature is
                // wider.  It differs system by system twice over — the region's first carries
                // the time signature and the full voice names, and a system opening on a `K:`
                // draws that change rather than a plain signature (#134) — so it is a function
                // rather than the two flat numbers it used to be.  Written once and asked
                // twice: of the *columns*, while the breaker is deciding where the systems
                // fall, and of the systems it decided on, so the justifier spends what the
                // breaker charged.
                let headerWidth = { (isOpening: Bool,
                                     signature: (Int) -> (KeySignature?, KeyChange?)) -> Double in
                    indent + (isOpening ? openingGutter : laterGutter)
                        + staffLead.indices.reduce(0.0) { widest, staffIndex in
                            let (key, change) = signature(staffIndex)
                            return max(widest, systemHeaderWidth(
                                clef: printedVoices[staffLead[staffIndex]].properties.clef,
                                keySignature: key, meter: isOpening ? regionMeter : nil,
                                metadata: metadata, staffSize: tuneConfig.staffSize,
                                keyChange: change))
                        }
                }
                let regionGroups = breaker.breakIntoGroups(
                    voiceLines, breaks: breaks, usableWidth: usableWidth,
                    grouping: selection.grouping,
                    headerWidth: { systemIndex, startColumn in
                        headerWidth(systemIndex == 0) { staffIndex in
                            (columnKeysPerStaff[staffIndex][startColumn],
                             columnsPerStaff[staffIndex][startColumn].keyChange)
                        }
                    })
                headerWidths += regionGroups.enumerated().map { index, group in
                    headerWidth(index == 0) { staffIndex in
                        (group.staves[staffIndex].keySignature,
                         group.staves[staffIndex].headerKeyChange)
                    }
                }
                // Every stave but the region's last ends on a `.hard` break, which the
                // breaker stamps on the last system it packed out of that stave.  Walking
                // the systems it produced therefore recovers the stave each one came from,
                // without the breaker having to carry the number through justification.
                var stave = region.staves.lowerBound
                for group in regionGroups {
                    staveOfGroup.append(stave)
                    if group.sourceForced { stave += 1 }
                }
                usableWidthOfGroup += regionGroups.map { _ in usableWidth }
                groups += regionGroups
            }

            // The line breaker marks the last system of whatever it was handed, and it was
            // handed one region at a time; only the last system of the last region ends the
            // tune.
            groups = groups.enumerated().map {
                $0.element.markingLastSystem($0.offset == groups.count - 1)
            }
            let tuneGroups = groups.isEmpty ? [] : justifier.justifyGroups(
                groups, usableWidth: usableWidth(on: pageSizes.opening),
                justifyLastSystem: layout.justifyLastSystem,
                systemHeaderWidths: headerWidths, systemUsableWidths: usableWidthOfGroup)

            // Build the title block for this tune per §6.1.3.
            // Title row baselineY values are tune-relative; the layout engine offsets
            // them to absolute page coordinates when placing the block.
            let tuneWriteFields: WriteFieldsConfig = {
                var wf = fileWriteFields
                for scope in tune.directives { wf.apply(scope.directive) }
                return wf
            }()
            // Centred on the page the tune's title actually prints on, which is the one it
            // opens on: a tune that turns the page landscape is titled across the landscape
            // width, not the document's (issue #158).
            var titleConfig = effectiveConfig
            titleConfig.pageSize = PageSize(width: pageSizes.opening.width,
                                            height: pageSizes.opening.height)
            let (titleRows, titleBlockHeight) = SpecTitleBlockBuilder(
                tune: tune, writeFields: tuneWriteFields, layoutConfig: titleConfig
            ).build()
            tuneBlocks.append(TuneBlock(systemGroups: tuneGroups, titleRows: titleRows,
                                        titleBlockHeight: titleBlockHeight, scale: layout.scale,
                                        graceNoteSpacing: layout.graceNoteSpacing,
                                        stemDirection: layout.stemDirection,
                                        straightFlags: layout.straightFlags,
                                        graceSlurs: layout.graceSlurs,
                                        pageBreaks: Self.forcedPageBreaks(
                                            tune.pageBreaks, staveOfGroup: staveOfGroup,
                                            portrait: config.pageSize)))
        }

        let firstPageNumber = Self.firstPageNumber(of: score)
        // The document's own answer, for a system that states none of its own — which is
        // every system of a `ResolvedLayout` assembled by hand rather than by the loop above.
        let emitter = SVGEmitter(config: effectiveConfig, metadata: metadata,
                                 stemDirection: fileLayout.stemDirection,
                                 firstPageNumber: firstPageNumber)
        let (layout, placements) = engine.layoutDocument(tuneBlocks,
                                                          firstPageNumber: firstPageNumber)
        let finalLayout = attachFooters(layout, score: score, config: effectiveConfig,
                                        firstPageNumber: firstPageNumber, fileLayout: fileLayout)
        // One `TuneBlock` is built per tune above, so a block's index is its tune's index.
        return RenderedDocument(pages: try emitter.emit(finalLayout), layout: finalLayout,
                                placements: placements)
    }

    // MARK: - Page breaks

    /// Resolves the tune's `%%newpage` directives from the staves they were written against
    /// to the systems they stand in front of (issue #140).
    ///
    /// A break lands on the first system of its stave.  Where that stave produced no system
    /// at all — a `%%score` region whose plan selects nothing is dropped whole — the break
    /// moves down to the next system there is, which keeps the music the author wanted on a
    /// fresh page on one.  A break past every system is kept, addressed one past the end:
    /// there is nothing left in this tune to move, so what it moves is the next tune.
    static func forcedPageBreaks(_ breaks: [PageBreak],
                                 staveOfGroup: [Int],
                                 portrait: PageSize) -> [ForcedPageBreak] {
        breaks.map { pageBreak in
            let group = staveOfGroup.firstIndex { $0 >= pageBreak.beforeStave }
                ?? staveOfGroup.count
            let size = pageBreak.landscape.map { Self.size(landscape: $0, portrait: portrait) }
            return ForcedPageBreak(beforeGroup: group, pageNumber: pageBreak.restartingAt,
                                   pageSize: size)
        }
    }

    // MARK: - Page size

    /// Where a tune's pages change size, and what they change to (issue #158).
    ///
    /// A page size cannot change part-way down a page, so every change is pinned to a
    /// `%%newpage` — the parser has already paired the two (see
    /// ``CeolKitModel/PageBreak/landscape``) — and this reads that pairing off as a function
    /// of position in the tune.  It has to be known *before* the music is packed: a landscape
    /// page is not only taller-or-shorter but wider, and a system is broken to the width of
    /// the page it lands on.
    struct PageSizePlan {
        /// The size in force when the tune opens: what the tune before it left standing,
        /// unless a break at stave 0 turns it.
        let opening: Size
        /// Each change, in stave order, as (the stave whose page it opens, the size).
        let changes: [(stave: Int, size: Size)]

        /// The size the tune leaves in force for whatever follows it.
        var closing: Size { changes.last?.size ?? opening }

        /// The staves a change lands on past the tune's first: the staves a ``PlanRegion``
        /// has to start at, so that no region spans two page sizes.
        var boundaries: Set<Int> { Set(changes.map(\.stave).filter { $0 > 0 }) }

        /// The size of the page stave `stave` lands on.
        func size(atStave stave: Int) -> Size {
            changes.last { $0.stave <= stave }?.size ?? opening
        }
    }

    static func pageSizePlan(for tune: Tune, inherited: Size,
                             portrait: PageSize) -> PageSizePlan {
        // Sorted by stave, and by source order within a stave — a `%%landscape` in the gap
        // above a tune and another in its header both land on the break before stave 0, and
        // the last one written wins.  `sorted(by:)` is not stable, so the source position
        // goes into the key rather than being relied on.
        let changes = tune.pageBreaks.enumerated()
            .compactMap { order, pageBreak -> (stave: Int, size: Size, order: Int)? in
                guard let landscape = pageBreak.landscape else { return nil }
                return (stave: pageBreak.beforeStave,
                        size: size(landscape: landscape, portrait: portrait),
                        order: order)
            }
            .sorted { ($0.stave, $0.order) < ($1.stave, $1.order) }
            .map { (stave: $0.stave, size: $0.size) }
        return PageSizePlan(
            opening: changes.last { $0.stave == 0 }?.size ?? inherited,
            changes: changes)
    }

    private static func size(landscape: Bool, portrait: PageSize) -> Size {
        let page = landscape ? portrait.landscape : portrait
        return Size(width: page.width, height: page.height)
    }

    // MARK: - Page numbering

    /// The number the document's first page prints, per `%%ceolkit:pagenumber` (issue #138).
    ///
    /// Last-wins, and read only from the first tune: the directive sets the number *before
    /// any output has been produced*, so the file preamble and the first tune's header are
    /// the only places it can mean anything, and the parser folds preamble directives into
    /// the first tune's list in source order, which puts both in one place.  A copy in a
    /// later tune's header would be asking to renumber pages already engraved — that is
    /// `%%newpage`'s job, not this directive's — and is ignored.
    ///
    /// Defaults to 1, which is what every document that does not use the directive gets, so
    /// the ordinary page number is `pageIndex + 1` exactly as it always was.
    static func firstPageNumber(of score: Score) -> Int {
        score.tunes.first?.directives.compactMap { scope -> Int? in
            if case .pageNumber(let n) = scope.directive { return n }
            return nil
        }.last ?? 1
    }

    // MARK: - Footer

    /// Stamps each page with the footer of the tune that owns it (issue #155).
    ///
    /// `%%footer` is scoped like every other stylesheet directive: written in the file header
    /// it governs the document, written in a tune header it governs that tune (ABC v2.2
    /// §4.23).  A page is therefore resolved from ``ResolvedPage/openingTuneIndex`` — the
    /// tune whose music opens it — rather than once for the whole document, so a tunebook
    /// whose tunes each name their own footer prints each one where it belongs instead of
    /// printing the last tune's on everything.
    ///
    /// `$T` and `%%dateformat` follow the same tune, for the same reason: a footer reading
    /// `$T` on page four should name the tune printed on page four.
    ///
    /// A page that names no tune — a layout assembled by hand — falls back to the document's
    /// own footer, which is what it has always got.
    private func attachFooters(_ layout: ResolvedLayout, score: Score, config: SVGRenderConfig,
                               firstPageNumber: Int, fileLayout: LayoutDirectives) -> ResolvedLayout {
        // Nothing anywhere in the document asks for a footer: the whole pass is skipped, and
        // no page gains an empty footer row it did not have before.
        guard score.footer?.isEmpty == false
                || score.tunes.contains(where: { $0.footer?.isEmpty == false })
        else { return layout }

        let pageCount = layout.pages.count
        let updatedPages = layout.pages.enumerated().map { pageIndex, page -> ResolvedPage in
            let tune = page.openingTuneIndex.map { score.tunes[$0] }
            let template = tune?.footer ?? score.footer
            let rows: [ResolvedTitleRow]
            if let template, !template.isEmpty {
                rows = buildFooterRows(
                    template: template,
                    pageNumber: page.pageNumber ?? firstPageNumber + pageIndex,
                    pageCount: pageCount,
                    title: (tune ?? score.tunes.first)?.titles.first?.value ?? "",
                    config: config,
                    // The footer sits against *this* page's margins, and a document can hold
                    // both orientations at once (issue #158), so the row is laid out on the
                    // page's own size rather than the document's.
                    pageSize: page.pageSize ?? layout.pageSize,
                    dateFormat: tune.map { fileLayout.layering($0).dateFormat }
                        ?? fileLayout.dateFormat)
            } else {
                rows = []
            }
            return ResolvedPage(systems: page.systems, titleRows: page.titleRows,
                                footerRows: rows, pageNumber: page.pageNumber,
                                openingTuneIndex: page.openingTuneIndex,
                                pageSize: page.pageSize)
        }
        return ResolvedLayout(pageSize: layout.pageSize, margins: layout.margins, pages: updatedPages)
    }

    private func buildFooterRows(template: String, pageNumber: Int, pageCount: Int,
                                  title: String, config: SVGRenderConfig,
                                  pageSize: Size,
                                  dateFormat: String? = nil) -> [ResolvedTitleRow] {
        let context = FooterContext(
            pageNumber: pageNumber, pageCount: pageCount,
            title: title,
            date: Self.currentDateString(format: dateFormat))
        let columns = FooterTemplate.columns(FooterTemplate.segments(of: template,
                                                                     context: context))
            .map(FooterTemplate.trimmed)

        let fontSize  = 12.0
        // Shift baseline up by the descender depth so the bottom of descenders (p, g, y, …)
        // lands precisely at the bottom margin line, not below it.
        let baselineY = pageSize.height - config.margins.bottom
            - fontSize * LibertinusSerifMetrics.descenderRatio
        let leftX     = config.margins.left
        let centerX   = pageSize.width / 2.0
        let rightX    = pageSize.width - config.margins.right

        let placements: [(column: [FooterSegment], x: Double, anchor: TextAnchor)]
        switch columns.count {
        case 1:
            placements = [(columns[0], centerX, .middle)]
        case 2:
            placements = [(columns[0], leftX,  .start),
                          (columns[1], rightX, .end)]
        default:
            placements = [(columns[0], leftX,   .start),
                          (columns[1], centerX, .middle),
                          (columns[2], rightX,  .end)]
        }

        let items = placements.flatMap {
            layOutFooterColumn($0.column, x: $0.x, anchor: $0.anchor,
                               baselineY: baselineY, fontSize: fontSize)
        }
        return items.isEmpty ? [] : [ResolvedTitleRow(items: items)]
    }

    /// Places one footer column, splitting it into separate items only where the author
    /// marked a `${…}` span.
    ///
    /// A column carrying no mark is laid out exactly as it always was — one item at the
    /// column's own anchor — so ordinary footers are byte-for-byte unchanged and no font is
    /// read to produce them.
    private func layOutFooterColumn(_ segments: [FooterSegment], x: Double, anchor: TextAnchor,
                                     baselineY: Double, fontSize: Double)
    -> [ResolvedTitleRow.Item] {
        let text = segments.map(\.text).joined()
        func wholeColumn(tag: String? = nil) -> [ResolvedTitleRow.Item] {
            guard tag != nil || !text.isEmpty else { return [] }
            return [.init(text: text, x: x, baselineY: baselineY, anchor: anchor,
                          fontSize: fontSize, tag: tag)]
        }

        guard segments.contains(where: { $0.tagName != nil }) else { return wholeColumn() }
        // A column that is nothing *but* the mark keeps the column's own anchor, so a
        // consumer stamping a wider string over it grows the way the column does — leftwards
        // at the right margin, outwards from the centre — instead of running off the page.
        if segments.count == 1, let name = segments[0].tagName { return wholeColumn(tag: name) }

        // A mark mixed in with other text has to become an element of its own, which means
        // measuring what precedes it. Without the bundled face there is nothing to measure
        // with, so the column falls back to one untagged run: the default text, correctly
        // drawn, and no substitution point — better than a footer laid out by guesswork.
        guard let face = OutlineFontSet.textFace() else { return wholeColumn() }
        var penX: Double
        switch anchor {
        case .start:  penX = x
        case .middle: penX = x - face.width(of: text, fontSize: fontSize) / 2
        case .end:    penX = x - face.width(of: text, fontSize: fontSize)
        }

        var items: [ResolvedTitleRow.Item] = []
        for segment in segments {
            if segment.tagName != nil || !segment.text.isEmpty {
                items.append(.init(text: segment.text, x: penX, baselineY: baselineY,
                                   anchor: .start, fontSize: fontSize, tag: segment.tagName))
            }
            penX += face.width(of: segment.text, fontSize: fontSize)
        }
        return items
    }

    private static func currentDateString(format: String? = nil, date: Date = Date()) -> String {
        guard let fmt = format else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        // Unescape \% → % (abc2svg always requires \%; abcm2ps requires it when value is unquoted).
        // The parser strips outer double-quotes, so a quoted value arrives without \% escaping.
        // Doing the unescape unconditionally is safe: it's a no-op when \% is absent.
        let unescaped = fmt.replacing(/\\%/, with: "%")
        var t = time_t(date.timeIntervalSince1970)
        var tmStruct = tm()
        localtime_r(&t, &tmStruct)
        var buffer = [CChar](repeating: 0, count: 256)
        strftime(&buffer, buffer.count, unescaped, &tmStruct)
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    // MARK: - Score directive application

    /// Returns a config with score-level directives applied.
    ///
    /// `%%landscape` written in the *file header* is the orientation the document opens in,
    /// and that is all this resolves: the parser promotes file-header directives into the
    /// first tune's list at ``Scope/fileGlobal``, so reading only those is what keeps a
    /// `%%landscape` written later — in the gap between two tunes, or in a tune header —
    /// from reaching back and reorienting pages already engraved (issue #158).  A change
    /// written later is a change *at a page break*, carried on ``CeolKitModel/PageBreak``
    /// instead, because a page size cannot change part-way down a page.  All other
    /// per-config values remain as supplied.
    ///
    /// `%%straightflags` and `%%graceslurs` used to be read here too, and were wrong in both
    /// directions for it: the first tune's copy governed the whole document and every later
    /// tune's was ignored outright (issue #156).  They are scoped directives, so they belong
    /// with the rest of them in ``LayoutDirectives`` — resolved from the file preamble for
    /// the document baseline, then per tune on top of it — and are carried to the emitter on
    /// the tune's own systems.
    private func applyingScoreDirectives(_ score: Score) -> SVGRenderConfig {
        var effective = config
        for scope in score.tunes.first?.directives ?? [] {
            guard case .fileGlobal = scope.scope else { continue }
            switch scope.directive {
            case .landscape(let on):
                effective.pageSize = on ? config.pageSize.landscape : config.pageSize
            default:
                break
            }
        }
        return effective
    }
}

// MARK: - Voice labels

private extension Tune {
    /// Whether any voice of this tune prints a name in the left gutter — which is what
    /// decides whether the renderer has to read a text face at all.
    var hasVoiceLabels: Bool {
        voices.contains { $0.properties.name != nil || $0.properties.subname != nil }
    }
}

// MARK: - Plan regions

private extension SystemGroup {
    /// The same group with `isLastSystem` set to `isLast` on every staff.
    func markingLastSystem(_ isLast: Bool) -> SystemGroup {
        guard isLastSystem != isLast else { return self }
        return SystemGroup(staves: staves.map {
            System(measures: $0.measures, isLastSystem: isLast, sourceForced: $0.sourceForced,
                   staveWasSplit: $0.staveWasSplit, clef: $0.clef,
                   keySignature: $0.keySignature, meter: $0.meter,
                   voiceLabel: $0.voiceLabel, voiceStemDirections: $0.voiceStemDirections,
                   headerKeyChange: $0.headerKeyChange)
        }, grouping: grouping)
    }
}
