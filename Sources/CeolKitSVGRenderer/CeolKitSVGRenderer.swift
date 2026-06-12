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

        var allSystems: [JustifiedSystem] = []
        var stemDirection: StemDirection = .auto

        for tune in score.tunes {
            var justifyLastSystem = effectiveConfig.justifyLastSystem
            for scope in tune.directives {
                switch scope.directive {
                case .pipeFormat(true):     stemDirection = .down
                case .justifyLast(let on):  justifyLastSystem = on
                default: break
                }
            }
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
                allSystems.append(contentsOf: justified)
            }
        }

        // Build the title block from the first tune's %%titleformat directive (if present).
        let (titleRows, titleBlockHeight) = buildTitleBlock(
            score: score,
            config: effectiveConfig
        )

        let emitter = SVGEmitter(config: effectiveConfig, metadata: metadata, stemDirection: stemDirection)
        let layout = engine.layout(allSystems, titleRows: titleRows, titleBlockHeight: titleBlockHeight)
        let finalLayout = attachFooters(layout, score: score, config: effectiveConfig)
        return try emitter.emit(finalLayout)
    }

    // MARK: - Title block

    private func buildTitleBlock(
        score: Score,
        config: SVGRenderConfig
    ) -> (rows: [ResolvedTitleRow], height: Double) {
        guard let tune = score.tunes.first else { return ([], 0) }

        var formatString: String? = nil
        for scope in tune.directives {
            if case .titleFormat(let fmt) = scope.directive {
                formatString = fmt
                break
            }
        }
        guard let fmt = formatString, !fmt.isEmpty else { return ([], 0) }

        let spec = TitleFormatParser.parse(fmt)
        let resolved = TitleResolver(tune: tune).resolve(spec)
        guard !resolved.isEmpty else { return ([], 0) }

        let lineHeight    = config.staffSize * 2.5
        let titleFontSize = 18.0
        let infoFontSize  = 12.0

        let leftX   = config.margins.left
        let centerX = config.pageSize.width / 2.0
        let rightX  = config.pageSize.width - config.margins.right

        var rows: [ResolvedTitleRow] = []
        for (rowIndex, row) in resolved.enumerated() {
            // Use a slightly larger font for the first row (typically the title).
            let fontSize = rowIndex == 0 ? titleFontSize : infoFontSize
            let baselineY = config.margins.top + lineHeight * Double(rowIndex + 1) - lineHeight * 0.25

            let isItalic = rowIndex > 0
            var items: [ResolvedTitleRow.Item] = []
            if let text = row.left {
                items.append(ResolvedTitleRow.Item(
                    text: text, x: leftX, baselineY: baselineY, anchor: .start,
                    fontSize: fontSize, isItalic: isItalic))
            }
            if let text = row.center {
                items.append(ResolvedTitleRow.Item(
                    text: text, x: centerX, baselineY: baselineY, anchor: .middle,
                    fontSize: fontSize, isItalic: isItalic))
            }
            if let text = row.right {
                items.append(ResolvedTitleRow.Item(
                    text: text, x: rightX, baselineY: baselineY, anchor: .end,
                    fontSize: fontSize, isItalic: isItalic))
            }
            if !items.isEmpty {
                rows.append(ResolvedTitleRow(items: items))
            }
        }

        let totalHeight = lineHeight * Double(resolved.count) + config.staffSize
        return (rows, totalHeight)
    }

    // MARK: - Footer

    private func attachFooters(_ layout: ResolvedLayout, score: Score, config: SVGRenderConfig) -> ResolvedLayout {
        guard let template = score.footer, !template.isEmpty else { return layout }
        let pageCount = layout.pages.count
        let updatedPages = layout.pages.enumerated().map { pageIndex, page -> ResolvedPage in
            let rows = buildFooterRows(template: template, pageNumber: pageIndex + 1,
                                       pageCount: pageCount, score: score, config: config)
            return ResolvedPage(systems: page.systems, titleRows: page.titleRows, footerRows: rows)
        }
        return ResolvedLayout(pageSize: layout.pageSize, margins: layout.margins, pages: updatedPages)
    }

    private func buildFooterRows(template: String, pageNumber: Int, pageCount: Int,
                                  score: Score, config: SVGRenderConfig) -> [ResolvedTitleRow] {
        let title   = score.tunes.first?.titles.first?.value ?? ""
        let dateStr = Self.currentDateString()

        var text = template
            .replacing(/\$P/, with: String(pageNumber))
            .replacing(/\$T/, with: title)
            .replacing(/\$D/, with: dateStr)
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

    private static func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    // MARK: - Score directive application

    /// Returns a config with score-level directives applied.
    ///
    /// `%%landscape` is a document-wide setting that the parser promotes into the
    /// first tune's directives.  All other per-config values remain as supplied.
    private func applyingScoreDirectives(_ score: Score) -> SVGRenderConfig {
        var effective = config
        for scope in score.tunes.first?.directives ?? [] {
            if case .landscape(let on) = scope.directive {
                effective.pageSize = on ? config.pageSize.landscape : config.pageSize
            }
        }
        return effective
    }
}
