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
        let sizer    = MeasureSizer(config: config, metadata: metadata)
        let breaker  = LineBreaker()
        let justifier = Justifier()
        let engine   = VerticalLayoutEngine(config: config, metadata: metadata)
        let emitter  = SVGEmitter(config: config, metadata: metadata)

        let usableWidth = config.pageSize.width - config.margins.left - config.margins.right

        var allSystems: [JustifiedSystem] = []

        for tune in score.tunes {
            for voice in tune.voices {
                let measures = voice.staves.flatMap { $0.measures }
                guard !measures.isEmpty else { continue }

                let pairs = measures.map { m in
                    (measure: sizer.size(m, unitNoteLength: tune.unitNoteLength),
                     breakAfter: ScoreLineBreak?.none)
                }
                let systems   = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                                        clef: voice.properties.clef)
                let justified = justifier.justify(systems, usableWidth: usableWidth,
                                                  justifyLastSystem: config.justifyLastSystem)
                allSystems.append(contentsOf: justified)
            }
        }

        let layout = engine.layout(allSystems)
        return try emitter.emit(layout)
    }
}
