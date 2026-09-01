import CeolKitModel

/// The glyph a clef is drawn with, octave transposition included (ABC v2.2 §4.6:
/// `clef=treble-8`, `clef=bass+8`, `clef=treble+15`).
///
/// SMuFL draws the numeral as part of the glyph, so an octave clef is a *substitution* for
/// the plain one rather than a second thing to place — which is why this is one function and
/// not a glyph plus an offset.  Both the width reserved for the clef and the drawing of it
/// go through here, so the two cannot disagree about which glyph the header holds.
///
/// Where a font has no octave form of a clef — SMuFL defines `cClef8vb` and no other shifted
/// C clef — the plain glyph is returned.  The transposition is a property of the voice and
/// has already been applied to the notes; only the reader's reminder of it is missing.
func clefGlyph(for spec: ClefSpec) -> SMuFLGlyph? {
    switch spec.clef {
    case .none:
        return nil
    case .treble:
        switch spec.octaveShift {
        case  8:  return .gClef8va
        case -8:  return .gClef8vb
        case  15: return .gClef15ma
        case -15: return .gClef15mb
        default:  return .gClef
        }
    case .bass, .baritone:
        switch spec.octaveShift {
        case  8:  return .fClef8va
        case -8:  return .fClef8vb
        case  15: return .fClef15ma
        case -15: return .fClef15mb
        default:  return .fClef
        }
    case .alto, .tenor, .soprano, .mezzoSoprano:
        return spec.octaveShift == -8 ? .cClef8vb : .cClef
    case .percussion:
        return .unpitchedPercussionClef1
    }
}

/// Horizontal space consumed by the clef glyph at the start of a system.
func clefHeaderWidth(for spec: ClefSpec, metadata: BravuraMetadata, staffSize: Double) -> Double {
    guard let glyph = clefGlyph(for: spec) else { return 0 }
    let glyphWidth = metadata.glyphBBoxes[glyph.rawValue].map { $0.width * staffSize }
        ?? (2.8 * staffSize)
    return glyphWidth + 0.5 * staffSize
}

/// Total horizontal space reserved before the first measure of a system.
///
/// Mirrors the `startWidth` calculation in `VerticalLayoutEngine` so that the
/// `LineBreaker` and `Justifier` can account for it when packing and stretching measures.
func systemHeaderWidth(
    clef: ClefSpec,
    keySignature: KeySignature?,
    meter: Meter?,
    metadata: BravuraMetadata,
    staffSize: Double
) -> Double {
    let clefW    = clefHeaderWidth(for: clef, metadata: metadata, staffSize: staffSize)
    let timeSigW = meter.map { timeSignatureWidth(for: $0, metadata: metadata, staffSize: staffSize) } ?? 0
    // When no time signature follows, use noteheadWidth as the key-sig trailing gap —
    // matching the same logic in VerticalLayoutEngine.
    let keySigTrailing: Double? = timeSigW > 0 ? nil : {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * staffSize } ?? staffSize * 1.2
    }()
    let keySigW = keySignature.map {
        keySignatureWidth(for: $0, clef: clef, metadata: metadata, staffSize: staffSize,
                          trailingGap: keySigTrailing)
    } ?? 0
    return clefW + keySigW + timeSigW
}
