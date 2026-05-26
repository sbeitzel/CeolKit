import Foundation

public struct BravuraMetadata: Sendable {

    public struct EngravingDefaults: Sendable {
        public let staffLineThickness: Double
        public let stemThickness: Double
        public let beamThickness: Double
        public let beamSpacing: Double
        public let legerLineThickness: Double
        public let legerLineExtension: Double
        public let thinBarlineThickness: Double
        public let thickBarlineThickness: Double
        public let barlineSeparation: Double
    }

    public struct BoundingBox: Sendable {
        public let neX: Double
        public let neY: Double
        public let swX: Double
        public let swY: Double

        public var width: Double { neX - swX }
        public var height: Double { neY - swY }
    }

    public let engravingDefaults: EngravingDefaults
    /// Bounding boxes in staff spaces; multiply by `staffSize` to get points.
    public let glyphBBoxes: [String: BoundingBox]
    /// Anchor points in staff spaces, keyed by glyph name then anchor name.
    /// Each anchor is `[x, y]` in staff spaces.
    public let glyphsWithAnchors: [String: [String: [Double]]]

    public static func load() throws -> BravuraMetadata {
        guard let url = Bundle.module.url(forResource: "bravura_metadata", withExtension: "json") else {
            throw BravuraMetadataError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(RawMetadata.self, from: data)
        return BravuraMetadata(raw: raw)
    }
}

public enum BravuraMetadataError: Error {
    case resourceNotFound
    case invalidBoundingBox(glyph: String)
}

// MARK: - Private decoding

private struct RawBBox: Decodable {
    let bBoxNE: [Double]
    let bBoxSW: [Double]
}

private struct RawMetadata: Decodable {
    let engravingDefaults: [String: Double]
    let glyphBBoxes: [String: RawBBox]
    let glyphsWithAnchors: [String: [String: [Double]]]
}

private extension BravuraMetadata {
    init(raw: RawMetadata) {
        let ed = raw.engravingDefaults
        engravingDefaults = EngravingDefaults(
            staffLineThickness: ed["staffLineThickness"] ?? 0,
            stemThickness:      ed["stemThickness"]      ?? 0,
            beamThickness:      ed["beamThickness"]      ?? 0,
            beamSpacing:        ed["beamSpacing"]        ?? 0,
            legerLineThickness: ed["legerLineThickness"] ?? 0,
            legerLineExtension: ed["legerLineExtension"] ?? 0,
            thinBarlineThickness:  ed["thinBarlineThickness"]  ?? 0,
            thickBarlineThickness: ed["thickBarlineThickness"] ?? 0,
            barlineSeparation:     ed["barlineSeparation"]     ?? 0
        )
        glyphBBoxes = raw.glyphBBoxes.compactMapValues { box in
            guard box.bBoxNE.count == 2, box.bBoxSW.count == 2 else { return nil }
            return BoundingBox(neX: box.bBoxNE[0], neY: box.bBoxNE[1],
                               swX: box.bBoxSW[0], swY: box.bBoxSW[1])
        }
        glyphsWithAnchors = raw.glyphsWithAnchors
    }
}
