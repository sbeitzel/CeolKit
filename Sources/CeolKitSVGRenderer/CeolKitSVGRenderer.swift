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
        let metadata = try BravuraMetadata.load()

        // Apply score-level directives that affect the whole document.
        // File-preamble directives are promoted to the first tune by the parser.
        let effectiveConfig = applyingScoreDirectives(score)

        let sizer     = MeasureSizer(config: effectiveConfig, metadata: metadata)
        let breaker   = LineBreaker()
        let justifier = Justifier()
        let engine    = VerticalLayoutEngine(config: effectiveConfig, metadata: metadata)

        let usableWidth = effectiveConfig.pageSize.width - effectiveConfig.margins.left - effectiveConfig.margins.right

        // File-preamble directives are promoted to the first tune by the parser.
        // Build a file-level WriteFieldsConfig from those file-global-scoped directives
        // so each tune can start from that baseline and layer its own on top.
        let fileWriteFields: WriteFieldsConfig = {
            var wf = WriteFieldsConfig.default
            for scope in score.tunes.first?.directives ?? [] where { if case .fileGlobal = scope.scope { true } else { false } }() {
                wf.apply(scope.directive)
            }
            return wf
        }()

        var tuneBlocks: [TuneBlock] = []
        var stemDirection: StemDirection = .auto
        var justifyLastSystem = effectiveConfig.justifyLastSystem

        for tune in score.tunes {
            for scope in tune.directives {
                switch scope.directive {
                case .pipeFormat(true):     stemDirection = .down
                case .justifyLast(let on):  justifyLastSystem = on
                default: break
                }
            }
            var tuneSystems: [JustifiedSystem] = []
            var meterForFirstSystem: Meter? = tune.meter
            for voice in tune.voices {
                // Build (measure, breakAfter) pairs honouring stave boundaries.
                // The semantic pass creates one Staff per source line-break, so the
                // last measure of every non-final stave gets a .hard score line-break.
                var pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] = []
                let staves = voice.staves
                for (si, stave) in staves.enumerated() {
                    let isLastStave = si == staves.count - 1
                    for (mi, m) in stave.measures.enumerated() {
                        let forceBreak = !isLastStave && mi == stave.measures.count - 1
                        pairs.append((
                            measure: sizer.size(m, unitNoteLength: tune.unitNoteLength),
                            breakAfter: forceBreak ? .hard : nil
                        ))
                    }
                }
                guard !pairs.isEmpty else { continue }
                // Header widths differ between the first system (has time sig) and later ones.
                let firstHeaderW = systemHeaderWidth(
                    clef: voice.properties.clef, keySignature: tune.key, meter: meterForFirstSystem,
                    metadata: metadata, staffSize: effectiveConfig.staffSize)
                let laterHeaderW = systemHeaderWidth(
                    clef: voice.properties.clef, keySignature: tune.key, meter: nil,
                    metadata: metadata, staffSize: effectiveConfig.staffSize)
                let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                                       firstSystemHeaderWidth: firstHeaderW,
                                                       laterSystemHeaderWidth: laterHeaderW,
                                                       clef: voice.properties.clef,
                                                       keySignature: tune.key,
                                                       meter: meterForFirstSystem)
                meterForFirstSystem = nil
                let headerWidths = systems.enumerated().map { i, _ in i == 0 ? firstHeaderW : laterHeaderW }
                let justified = justifier.justify(systems, usableWidth: usableWidth,
                                                  justifyLastSystem: justifyLastSystem,
                                                  systemHeaderWidths: headerWidths)
                tuneSystems.append(contentsOf: justified)
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
            tuneBlocks.append(TuneBlock(systems: tuneSystems, titleRows: titleRows,
                                        titleBlockHeight: titleBlockHeight))
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
