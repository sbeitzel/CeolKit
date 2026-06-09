import CeolKitModel

/// Horizontal space consumed by the clef glyph at the start of a system.
func clefHeaderWidth(for spec: ClefSpec, metadata: BravuraMetadata, staffSize: Double) -> Double {
    let name: String
    switch spec.clef {
    case .none:                                  return 0
    case .treble:                                name = "gClef"
    case .bass, .baritone:                       name = "fClef"
    case .alto, .tenor, .soprano, .mezzoSoprano: name = "cClef"
    case .percussion:                            name = "unpitchedPercussionClef1"
    }
    let glyphWidth = metadata.glyphBBoxes[name].map { $0.width * staffSize } ?? (2.8 * staffSize)
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
        keySignatureWidth(for: $0, metadata: metadata, staffSize: staffSize, trailingGap: keySigTrailing)
    } ?? 0
    return clefW + keySigW + timeSigW
}
