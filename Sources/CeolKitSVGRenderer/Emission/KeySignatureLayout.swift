import CeolKitModel

/// A single accidental glyph in a key signature and its vertical position on the staff.
///
/// Staff position 0 = bottom line of the staff, 8 = top line, counting one position
/// per diatonic step. Which pitch a position names depends on the clef, so the
/// positions are produced per clef by `keyAccidentals(for:clef:)`.
struct KeyAccidental: Sendable {
    let glyph: SMuFLGlyph      // .accidentalSharp or .accidentalFlat
    let staffPosition: Int
}

/// Returns the ordered list of accidentals to draw for `key` on a staff carrying `clef`.
///
/// Returns an empty array for `K:none`, highland-pipe keys, keys with no accidentals,
/// and clefs that carry no key signature (`percussion`, `none`).
///
/// The positions are per clef because a key signature names pitches, not offsets from
/// the staff top: F♯ sits on the top line in treble and on the fourth line in bass.
/// An octave shift on the clef (`treble+8`) does not move them — the shifted clef still
/// names the same staff lines.
func keyAccidentals(for key: KeySignature, clef: ClefSpec) -> [KeyAccidental] {
    guard key.mode != .none,
          key.mode != .highlandPipes,
          key.mode != .highlandPipesNoSignature,
          let tonic = key.tonic,
          let table = signatureTable(for: clef.clef) else { return [] }

    let cof = circleOfFifthsPosition(tonic: tonic, mode: key.mode)

    if cof > 0 {
        return (0..<min(cof, 7)).map {
            KeyAccidental(glyph: .accidentalSharp, staffPosition: table.sharps[$0])
        }
    } else if cof < 0 {
        return (0..<min(-cof, 7)).map {
            KeyAccidental(glyph: .accidentalFlat, staffPosition: table.flats[$0])
        }
    }
    return []
}

/// Total horizontal space (in points) reserved for a key signature header segment.
///
/// - Parameter trailingGap: Space to reserve after the last accidental glyph.
///   Defaults to `staffSize * 0.5`. Pass `noteheadWidth` when no time signature
///   follows, so the gap to the first bar line equals one note head.
func keySignatureWidth(for key: KeySignature, clef: ClefSpec, metadata: BravuraMetadata,
                        staffSize: Double, trailingGap: Double? = nil) -> Double {
    let accs = keyAccidentals(for: key, clef: clef)
    guard !accs.isEmpty else { return 0 }
    let glyphW    = metadata.glyphBBoxes["accidentalSharp"].map { $0.width * staffSize } ?? staffSize * 0.75
    let interGap  = staffSize * 0.1
    let trailing  = trailingGap ?? staffSize * 0.5
    return Double(accs.count) * (glyphW + interGap) + trailing
}

// MARK: - Private

/// The staff positions a key signature's accidentals occupy on one clef, in
/// circle-of-fifths order (F C G D A E B for sharps, B E A D G C F for flats).
private struct SignatureTable {
    let sharps: [Int]
    let flats: [Int]
}

/// The engraved accidental positions for `clef`, or `nil` for a clef that carries
/// no key signature.
///
/// Each table is the conventional engraving rather than a shift of the treble one:
/// the C clefs place individual accidentals an octave away from a plain transposition
/// so the whole signature stays on the staff.
private func signatureTable(for clef: Clef) -> SignatureTable? {
    switch clef {
    // Bottom line E4. F♯5 top line, G♯5 the space above the staff, F♭4 the first space.
    case .treble:
        return SignatureTable(sharps: [8, 5, 9, 6, 3, 7, 4], flats: [4, 7, 3, 6, 2, 5, 1])
    // Bottom line G2 — every position two below treble. F♭2 sits below the bottom
    // line; a key signature draws no ledger line for it.
    case .bass:
        return SignatureTable(sharps: [6, 3, 7, 4, 1, 5, 2], flats: [2, 5, 1, 4, 0, 3, -1])
    // F clef on line 3: bottom line B2.
    case .baritone:
        return SignatureTable(sharps: [4, 8, 5, 2, 6, 3, 7], flats: [7, 3, 6, 2, 5, 1, 4])
    // C clef on line 3: bottom line F3.
    case .alto:
        return SignatureTable(sharps: [7, 4, 8, 5, 2, 6, 3], flats: [3, 6, 2, 5, 1, 4, 0])
    // C clef on line 4: bottom line D3. F♯ starts an octave below the treble pattern.
    case .tenor:
        return SignatureTable(sharps: [2, 6, 3, 7, 4, 8, 5], flats: [5, 8, 4, 7, 3, 6, 2])
    // C clef on line 1: bottom line C4.
    case .soprano:
        return SignatureTable(sharps: [3, 7, 4, 8, 5, 2, 6], flats: [6, 2, 5, 1, 4, 0, 3])
    // C clef on line 2: bottom line A3.
    case .mezzoSoprano:
        return SignatureTable(sharps: [5, 2, 6, 3, 7, 4, 8], flats: [8, 4, 7, 3, 6, 2, 5])
    // Neither staff carries pitch, so neither carries a key signature.
    case .percussion, .none:
        return nil
    }
}

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
