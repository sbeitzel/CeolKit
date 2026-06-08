import CeolKitModel

/// A single accidental glyph in a key signature and its vertical position on the staff.
///
/// Staff position 0 = bottom line of treble staff (E4); 8 = top line (F5).
struct KeyAccidental: Sendable {
    let glyph: SMuFLGlyph      // .accidentalSharp or .accidentalFlat
    let staffPosition: Int
}

/// Returns the ordered list of accidentals to draw for `key` on a treble-clef staff.
///
/// Returns an empty array for `K:none`, highland-pipe keys, and keys with no accidentals.
func keyAccidentals(for key: KeySignature) -> [KeyAccidental] {
    guard key.mode != .none,
          key.mode != .highlandPipes,
          key.mode != .highlandPipesNoSignature,
          let tonic = key.tonic else { return [] }

    let cof = circleOfFifthsPosition(tonic: tonic, mode: key.mode)

    if cof > 0 {
        let positions = [8, 5, 2, 6, 3, 7, 4]   // F C G D A E B on treble staff
        return (0..<min(cof, 7)).map { KeyAccidental(glyph: .accidentalSharp, staffPosition: positions[$0]) }
    } else if cof < 0 {
        let positions = [4, 7, 3, 6, 2, 5, 8]   // B E A D G C F on treble staff
        return (0..<min(-cof, 7)).map { KeyAccidental(glyph: .accidentalFlat, staffPosition: positions[$0]) }
    }
    return []
}

/// Total horizontal space (in points) reserved for a key signature header segment.
func keySignatureWidth(for key: KeySignature, metadata: BravuraMetadata, staffSize: Double) -> Double {
    let accs = keyAccidentals(for: key)
    guard !accs.isEmpty else { return 0 }
    let glyphW = metadata.glyphBBoxes["accidentalSharp"].map { $0.width * staffSize } ?? staffSize * 0.75
    let gap = staffSize * 0.1
    return Double(accs.count) * (glyphW + gap) + staffSize * 0.5
}

// MARK: - Private

/// Maps a tonic+mode pair to a circle-of-fifths position.
///
/// Positive = that many sharps; negative = that many flats.
private func circleOfFifthsPosition(tonic: PitchClass, mode: Mode) -> Int {
    let fifths: [DiatonicStep: Int] = [.f: -1, .c: 0, .g: 1, .d: 2, .a: 3, .e: 4, .b: 5]
    let base          = fifths[tonic.step, default: 0]
    // Each chromatic semitone on the tonic shifts the CoF by ±7 (circle-of-fifths arithmetic).
    // Only applies for standard (denominator == 1) alterations; microtonal tonicss are unusual.
    let sharpsFromAlt = tonic.alteration.denominator == 1 ? tonic.alteration.numerator * 7 : 0
    let offsets: [Mode: Int] = [
        .major: 0, .ionian: 0, .lydian: 1,
        .mixolydian: -1,
        .dorian: -2,
        .minor: -3, .aeolian: -3,
        .phrygian: -4,
        .locrian: -5,
    ]
    return base + sharpsFromAlt + (offsets[mode] ?? 0)
}
