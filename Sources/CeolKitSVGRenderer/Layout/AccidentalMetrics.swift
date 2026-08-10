import Foundation
import CeolKitModel

/// Horizontal geometry of an accidental drawn to the left of its notehead.
///
/// The sizer reserves the space and the emitter draws into it, so both derive their numbers
/// from here.  Every measurement comes from the glyph's own bounding box: accidentals differ
/// in width by more than a factor of two (`accidentalNatural` 0.672 staff spaces against
/// `accidentalDoubleFlat` 1.644), so a single fixed offset cannot serve them all.
struct AccidentalMetrics {
    /// Clearance between the accidental glyph's right edge and the notehead's left edge,
    /// in staff spaces.
    static let gap = 0.12

    /// Offset used when a glyph is missing from the font metadata.
    static let fallbackWidth = 0.75

    private let staffSize: Double
    private let metadata: BravuraMetadata

    init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        self.staffSize = config.staffSize
        self.metadata = metadata
    }

    /// Rendered width of the accidental glyph for `alteration`, or `nil` when it has no
    /// glyph in the v0.1 set (microtonal accidentals) and so draws nothing.
    ///
    /// - Parameter scale: glyph scale relative to a normal note — `GraceMetrics.scale`
    ///   for a grace note, `1.0` otherwise.
    func width(for alteration: Alteration, scale: Double = 1.0) -> Double? {
        guard let glyph = SMuFLGlyph.accidental(for: alteration) else { return nil }
        let bboxWidth = metadata.glyphBBoxes[glyph.rawValue]?.width ?? Self.fallbackWidth
        return bboxWidth * staffSize * scale
    }

    /// Distance from the notehead's left edge to the accidental glyph's left edge: the glyph's
    /// own width plus a clearance gap.  This is the space the accidental needs reserved to the
    /// left of the note, and the offset the emitter draws it at.
    func offset(for alteration: Alteration, scale: Double = 1.0) -> Double {
        guard let w = width(for: alteration, scale: scale) else { return 0 }
        return w + Self.gap * staffSize * scale
    }

    /// Space to reserve left of a notehead for its accidental, if it has one.
    func reservation(for accidental: Alteration?, scale: Double = 1.0) -> Double {
        accidental.map { offset(for: $0, scale: scale) } ?? 0
    }
}

extension SMuFLGlyph {
    /// The accidental glyph for a semantic alteration, or `nil` for microtonal alterations,
    /// which have no glyph in the v0.1 set.
    static func accidental(for alteration: Alteration) -> SMuFLGlyph? {
        switch (alteration.numerator, alteration.denominator) {
        case (1, 1):  return .accidentalSharp
        case (-1, 1): return .accidentalFlat
        case (0, _):  return .accidentalNatural
        case (2, 1):  return .accidentalDoubleSharp
        case (-2, 1): return .accidentalDoubleFlat
        default:      return nil
        }
    }
}
