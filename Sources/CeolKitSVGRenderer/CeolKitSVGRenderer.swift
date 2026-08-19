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
        let metadata = try BravuraMetadata.load()

        // Apply score-level directives that affect the whole document.
        // File-preamble directives are promoted to the first tune by the parser.
        let effectiveConfig = applyingScoreDirectives(score)

        let breaker   = LineBreaker(overflowTolerance: effectiveConfig.lineOverflowTolerance)
        let justifier = Justifier(maxStretch: effectiveConfig.maxSystemStretch)
        let engine    = VerticalLayoutEngine(config: effectiveConfig, metadata: metadata)

        let usableWidth = effectiveConfig.pageSize.width - effectiveConfig.margins.left - effectiveConfig.margins.right

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

        var tuneBlocks: [TuneBlock] = []
        var stemDirection: StemDirection = .auto
        var justifyLastSystem = effectiveConfig.justifyLastSystem
        // %%ceolkit:scale is tune-scoped but sticky: a preamble value governs every following
        // tune until a later tune header overrides it. %%ceolkit:gracenotespacing behaves the
        // same way.
        var scale = 1.0
        var graceNoteSpacing = effectiveConfig.graceNoteSpacing

        for tune in score.tunes {
            for scope in tune.directives {
                switch scope.directive {
                case .pipeFormat(true):     stemDirection = .down
                case .justifyLast(let on):  justifyLastSystem = on
                case .scale(let factor):    scale = factor
                case .graceNoteSpacing(let step): graceNoteSpacing = step
                default: break
                }
            }
            // The music scales; the page does not. Sizing and header widths are therefore
            // derived from a per-tune staff size, while `usableWidth` stays absolute.
            var tuneConfig = effectiveConfig.scaled(by: scale)
            // A ratio within the grace group, not a size derived from the staff, so it is
            // set after `scaled(by:)` and never multiplied by the scale factor.
            tuneConfig.graceNoteSpacing = graceNoteSpacing
            let sizer = MeasureSizer(config: tuneConfig, metadata: metadata)

            // A voice a `V:` declared and the body never wrote to is in the model so a
            // `%%score` plan can name it, but it has no music to engrave. Dropping it here
            // rather than downstream matters: the aligner would pad it with invisible rests
            // on every line and warn that the voices disagree, drawing a staff of silence
            // the source never asked for.
            let printedVoices = tune.voices.filter { !$0.isEmpty }

            // Bring the voices into agreement about how much music each source line holds,
            // so the break points chosen below are legal for every one of them. Voices that
            // disagree are padded and warned about rather than laid out sequentially.
            let alignedStaves = VoiceAligner.align(printedVoices, into: &diagnostics)

            // Flatten the aligned staves into one measure column per bar, carrying the
            // stave boundaries as .hard breaks: the semantic pass makes one Staff per source
            // line-break, so the last column of every non-final stave forces a system break.
            var breaks: [ScoreLineBreak?] = []
            var columnsPerVoice = [[SizedMeasure]](repeating: [], count: printedVoices.count)
            for (si, stave) in alignedStaves.enumerated() {
                let isLastStave = si == alignedStaves.count - 1
                for column in 0..<stave.measureCount {
                    breaks.append(!isLastStave && column == stave.measureCount - 1 ? .hard : nil)
                    for voiceIndex in printedVoices.indices {
                        columnsPerVoice[voiceIndex].append(
                            sizer.size(stave.measures[voiceIndex][column],
                                       unitNoteLength: tune.unitNoteLength))
                    }
                }
            }

            var tuneGroups: [JustifiedSystemGroup] = []
            if !breaks.isEmpty {
                let voiceLines = printedVoices.enumerated().map { index, voice in
                    LineBreaker.VoiceLine(measures: columnsPerVoice[index],
                                          clef: voice.properties.clef,
                                          keySignature: tune.key,
                                          meter: tune.meter)
                }
                // Header widths differ between the first system (has time sig) and later
                // ones, and are the max across the group: the staves of a system have to
                // start at the same x even when one voice's clef or key signature is wider.
                let firstHeaderW = printedVoices.reduce(0.0) { widest, voice in
                    max(widest, systemHeaderWidth(clef: voice.properties.clef, keySignature: tune.key,
                                                  meter: tune.meter, metadata: metadata,
                                                  staffSize: tuneConfig.staffSize))
                }
                let laterHeaderW = printedVoices.reduce(0.0) { widest, voice in
                    max(widest, systemHeaderWidth(clef: voice.properties.clef, keySignature: tune.key,
                                                  meter: nil, metadata: metadata,
                                                  staffSize: tuneConfig.staffSize))
                }
                let groups = breaker.breakIntoGroups(voiceLines, breaks: breaks,
                                                     usableWidth: usableWidth,
                                                     firstSystemHeaderWidth: firstHeaderW,
                                                     laterSystemHeaderWidth: laterHeaderW)
                let headerWidths = groups.indices.map { $0 == 0 ? firstHeaderW : laterHeaderW }
                tuneGroups = justifier.justifyGroups(groups, usableWidth: usableWidth,
                                                     justifyLastSystem: justifyLastSystem,
                                                     systemHeaderWidths: headerWidths)
            }

            // Build the title block for this tune per §6.1.3.
            // Title row baselineY values are tune-relative; the layout engine offsets
            // them to absolute page coordinates when placing the block.
            let tuneWriteFields: WriteFieldsConfig = {
                var wf = fileWriteFields
                for scope in tune.directives { wf.apply(scope.directive) }
                return wf
            }()
            let (titleRows, titleBlockHeight) = SpecTitleBlockBuilder(
                tune: tune, writeFields: tuneWriteFields, layoutConfig: effectiveConfig
            ).build()
            tuneBlocks.append(TuneBlock(systemGroups: tuneGroups, titleRows: titleRows,
                                        titleBlockHeight: titleBlockHeight, scale: scale,
                                        graceNoteSpacing: graceNoteSpacing))
        }

        let emitter = SVGEmitter(config: effectiveConfig, metadata: metadata, stemDirection: stemDirection)
        let layout = engine.layout(tuneBlocks)
        let finalLayout = attachFooters(layout, score: score, config: effectiveConfig)
        return try emitter.emit(finalLayout)
    }

    // MARK: - Footer

    private func attachFooters(_ layout: ResolvedLayout, score: Score, config: SVGRenderConfig) -> ResolvedLayout {
        guard let template = score.footer, !template.isEmpty else { return layout }
        // Find the last %%dateformat directive (last-wins across preamble and tune header).
        let dateFormat = score.tunes.first?.directives.compactMap { scope -> String? in
            if case .dateFormat(let fmt) = scope.directive { return fmt }
            return nil
        }.last
        let pageCount = layout.pages.count
        let updatedPages = layout.pages.enumerated().map { pageIndex, page -> ResolvedPage in
            let rows = buildFooterRows(template: template, pageNumber: pageIndex + 1,
                                       pageCount: pageCount, score: score, config: config,
                                       dateFormat: dateFormat)
            return ResolvedPage(systems: page.systems, titleRows: page.titleRows, footerRows: rows)
        }
        return ResolvedLayout(pageSize: layout.pageSize, margins: layout.margins, pages: updatedPages)
    }

    private func buildFooterRows(template: String, pageNumber: Int, pageCount: Int,
                                  score: Score, config: SVGRenderConfig,
                                  dateFormat: String? = nil) -> [ResolvedTitleRow] {
        let title   = score.tunes.first?.titles.first?.value ?? ""
        let dateStr = Self.currentDateString(format: dateFormat)

        var text = template
            .replacing(/\$P/, with: String(pageNumber))
            .replacing(/\$T/, with: title)
            .replacing(/\$D/, with: dateStr)
            .replacing(/\$d/, with: dateStr)
        text = text.replacing(/\\t/, with: "\t")

        let parts     = text.components(separatedBy: "\t")
        let fontSize  = 12.0
        // Shift baseline up by the descender depth so the bottom of descenders (p, g, y, …)
        // lands precisely at the bottom margin line, not below it.
        let baselineY = config.pageSize.height - config.margins.bottom
            - fontSize * LibertinusSerifMetrics.descenderRatio
        let leftX     = config.margins.left
        let centerX   = config.pageSize.width / 2.0
        let rightX    = config.pageSize.width - config.margins.right

        var items: [ResolvedTitleRow.Item] = []
        switch parts.count {
        case 1:
            let t = parts[0].trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                items.append(.init(text: t, x: centerX, baselineY: baselineY,
                                   anchor: .middle, fontSize: fontSize))
            }
        case 2:
            let l = parts[0].trimmingCharacters(in: .whitespaces)
            let r = parts[1].trimmingCharacters(in: .whitespaces)
            if !l.isEmpty { items.append(.init(text: l, x: leftX,  baselineY: baselineY, anchor: .start, fontSize: fontSize)) }
            if !r.isEmpty { items.append(.init(text: r, x: rightX, baselineY: baselineY, anchor: .end,   fontSize: fontSize)) }
        default:
            let l = parts[0].trimmingCharacters(in: .whitespaces)
            let c = parts[1].trimmingCharacters(in: .whitespaces)
            let r = parts[2].trimmingCharacters(in: .whitespaces)
            if !l.isEmpty { items.append(.init(text: l, x: leftX,   baselineY: baselineY, anchor: .start,  fontSize: fontSize)) }
            if !c.isEmpty { items.append(.init(text: c, x: centerX, baselineY: baselineY, anchor: .middle, fontSize: fontSize)) }
            if !r.isEmpty { items.append(.init(text: r, x: rightX,  baselineY: baselineY, anchor: .end,    fontSize: fontSize)) }
        }

        return items.isEmpty ? [] : [ResolvedTitleRow(items: items)]
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
    /// `%%landscape` is a document-wide setting that the parser promotes into the
    /// first tune's directives.  All other per-config values remain as supplied.
    private func applyingScoreDirectives(_ score: Score) -> SVGRenderConfig {
        var effective = config
        for scope in score.tunes.first?.directives ?? [] {
            switch scope.directive {
            case .landscape(let on):
                effective.pageSize = on ? config.pageSize.landscape : config.pageSize
            case .straightFlags(let on):
                effective.straightFlags = on
            case .graceSlurs(let on):
                effective.graceSlurs = on
            default:
                break
            }
        }
        return effective
    }
}
