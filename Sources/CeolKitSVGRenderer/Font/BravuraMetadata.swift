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
        public let repeatBarlineDotSeparation: Double
        /// Thickness of a slur at its two ends; SMuFL models a slur as tapered, so this is
        /// the thinner of the pair.
        public let slurEndpointThickness: Double
        /// Thickness of a slur at its midpoint — the thicker of the pair.
        public let slurMidpointThickness: Double
        public let tieEndpointThickness: Double
        public let tieMidpointThickness: Double
    }

    public struct BoundingBox: Sendable {
        public let neX: Double
        public let neY: Double
        public let swX: Double
        public let swY: Double

        public var width: Double { neX - swX }
        public var height: Double { neY - swY }
    }

    /// The `fontVersion` declared by the metadata — the only reliable way to tell which
    /// release of the face the metadata was generated from.
    public let fontVersion: Double
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

/// The engraving defaults CeolKit consumes, named to match the SMuFL metadata keys.
///
/// Decoded as an explicit struct rather than a `[String: Double]` because the object is
/// not homogeneous: SMuFL 1.4 / Bravura 1.392 added `textFontFamily`, an array of strings,
/// which makes a dictionary decode fail outright with `typeMismatch`. Naming only what is
/// used means later releases can add keys of any shape without breaking `load()`.
///
/// Every value is optional so a face that omits one still decodes; the missing default
/// falls back to `0`, as it did when these were dictionary lookups.
///
/// The keys Bravura supplies that are deliberately *not* read describe notation this
/// renderer does not yet draw: `bracketThickness`, `subBracketThickness`,
/// `dashedBarlineDashLength`, `dashedBarlineGapLength`, `dashedBarlineThickness`,
/// `hairpinThickness`, `octaveLineThickness`, `pedalLineThickness`,
/// `repeatEndingLineThickness`, `textEnclosureThickness`, `tupletBracketThickness`,
/// `lyricLineThickness`, `arrowShaftThickness`, `hBarThickness`, `textFontFamily`.
/// Each becomes worth decoding when the corresponding mark starts being emitted, not
/// before — an unused property is a value nothing can hold the renderer to.
private struct RawEngravingDefaults: Decodable {
    let staffLineThickness: Double?
    let stemThickness: Double?
    let beamThickness: Double?
    let beamSpacing: Double?
    let legerLineThickness: Double?
    let legerLineExtension: Double?
    let thinBarlineThickness: Double?
    let thickBarlineThickness: Double?
    let barlineSeparation: Double?
    let repeatBarlineDotSeparation: Double?
    let slurEndpointThickness: Double?
    let slurMidpointThickness: Double?
    let tieEndpointThickness: Double?
    let tieMidpointThickness: Double?
}

private struct RawMetadata: Decodable {
    let fontVersion: Double
    let engravingDefaults: RawEngravingDefaults
    let glyphBBoxes: [String: RawBBox]
    let glyphsWithAnchors: [String: [String: [Double]]]
}

private extension BravuraMetadata {
    init(raw: RawMetadata) {
        fontVersion = raw.fontVersion
        let ed = raw.engravingDefaults
        engravingDefaults = EngravingDefaults(
            staffLineThickness: ed.staffLineThickness ?? 0,
            stemThickness:      ed.stemThickness      ?? 0,
            beamThickness:      ed.beamThickness      ?? 0,
            beamSpacing:        ed.beamSpacing        ?? 0,
            legerLineThickness: ed.legerLineThickness ?? 0,
            legerLineExtension: ed.legerLineExtension ?? 0,
            thinBarlineThickness:  ed.thinBarlineThickness  ?? 0,
            thickBarlineThickness: ed.thickBarlineThickness ?? 0,
            barlineSeparation:     ed.barlineSeparation     ?? 0,
            // Unlike the thicknesses above, zero here does not merely draw something thin —
            // it draws nothing at all, or stacks the repeat dots against the bar line. A face
            // omitting these gets Bravura's values, the reference face SMuFL publishes.
            repeatBarlineDotSeparation: ed.repeatBarlineDotSeparation ?? 0.16,
            slurEndpointThickness: ed.slurEndpointThickness ?? 0.1,
            slurMidpointThickness: ed.slurMidpointThickness ?? 0.22,
            tieEndpointThickness:  ed.tieEndpointThickness  ?? 0.1,
            tieMidpointThickness:  ed.tieMidpointThickness  ?? 0.22
        )
        glyphBBoxes = raw.glyphBBoxes.compactMapValues { box in
            guard box.bBoxNE.count == 2, box.bBoxSW.count == 2 else { return nil }
            return BoundingBox(neX: box.bBoxNE[0], neY: box.bBoxNE[1],
                               swX: box.bBoxSW[0], swY: box.bBoxSW[1])
        }
        glyphsWithAnchors = raw.glyphsWithAnchors
    }
}
