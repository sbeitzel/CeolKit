import CeolKitModel

/// Total horizontal space (in points) reserved for a time signature header segment.
///
/// Returns 0 for `free` and `complex` meters that have no standard glyph representation.
func timeSignatureWidth(for meter: Meter, metadata: BravuraMetadata, staffSize: Double) -> Double {
    let noteheadW = metadata.glyphBBoxes["noteheadBlack"].map { $0.width * staffSize } ?? staffSize * 1.2
    let gap = noteheadW * 1.5
    switch meter {
    case .commonTime:
        let w = metadata.glyphBBoxes["timeSigCommon"].map { $0.width * staffSize } ?? staffSize * 1.5
        return w + gap
    case .cutTime:
        let w = metadata.glyphBBoxes["timeSigCutCommon"].map { $0.width * staffSize } ?? staffSize * 1.5
        return w + gap
    case .fraction(let num, let den):
        let maxDigits = max(String(num).count, String(den).count)
        let glyphW = metadata.glyphBBoxes["timeSig4"].map { $0.width * staffSize } ?? staffSize * 0.9
        return Double(maxDigits) * glyphW + gap
    case .free, .complex:
        return 0
    }
}
