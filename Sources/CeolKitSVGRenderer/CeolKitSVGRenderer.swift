import CeolKitModel
import CeolKitRenderer

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

        let sizer    = MeasureSizer(config: effectiveConfig, metadata: metadata)
        let breaker  = LineBreaker()
        let justifier = Justifier()
        let engine   = VerticalLayoutEngine(config: effectiveConfig, metadata: metadata)

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
                let systems   = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
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

        let emitter = SVGEmitter(config: effectiveConfig, metadata: metadata, stemDirection: stemDirection)
        let layout = engine.layout(allSystems)
        return try emitter.emit(layout)
    }

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
