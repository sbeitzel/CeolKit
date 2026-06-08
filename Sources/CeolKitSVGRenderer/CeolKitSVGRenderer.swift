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
            for scope in tune.directives {
                if case .pipeFormat(true) = scope.directive {
                    stemDirection = .down
                }
            }
            for voice in tune.voices {
                let measures = voice.staves.flatMap { $0.measures }
                guard !measures.isEmpty else { continue }

                let pairs = measures.map { m in
                    (measure: sizer.size(m, unitNoteLength: tune.unitNoteLength),
                     breakAfter: ScoreLineBreak?.none)
                }
                let systems   = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                                        clef: voice.properties.clef,
                                                        keySignature: tune.key)
                let justified = justifier.justify(systems, usableWidth: usableWidth,
                                                  justifyLastSystem: effectiveConfig.justifyLastSystem)
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
