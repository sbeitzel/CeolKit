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

/// How much smaller than the staff-head clef a clef change part way through a staff is
/// drawn — abcm2ps's proportion (its `sbclef` is drawn at 0.037 against the head's 0.045).
let clefChangeScale = 0.8

/// Horizontal space a clef change part way through a staff takes: the small clef and the
/// gap after it (issue #223).
func clefChangeWidth(for spec: ClefSpec, metadata: BravuraMetadata, staffSize: Double) -> Double {
    guard let glyph = clefGlyph(for: spec) else { return 0 }
    let glyphWidth = metadata.glyphBBoxes[glyph.rawValue].map { $0.width * staffSize }
        ?? (2.8 * staffSize)
    return glyphWidth * clefChangeScale + 0.8 * staffSize
}

/// The clef a `K:` written before any of the bar's music moved the staff to — the change
/// abcm2ps draws before the bar line rather than after it, so it belongs to the end of the
/// bar before (issue #223).  `nil` where the bar opens with no such change.
func leadingClefChange(of measure: Measure) -> ClefSpec? {
    var clef: ClefSpec? = nil
    for event in measure.events {
        switch event {
        case .clefChange(let c):                                clef = c
        case .spacer, .directiveAnchor, .tempoChange:           continue
        case .note, .rest, .chord, .grace, .tuplet:             return clef
        }
    }
    return clef
}

/// Whether `event` is music a clef change can come after, rather than furniture it can
/// stand before.  What decides that a change is ``leadingClefChange(of:)``.
func isMusic(_ event: Event) -> Bool {
    switch event {
    case .note, .rest, .chord, .grace, .tuplet:                       return true
    case .spacer, .directiveAnchor, .tempoChange, .clefChange:        return false
    }
}

/// The clef the staff is in after `measure`, given the one it entered in.
func clefLeaving(_ measure: Measure, entering clef: ClefSpec) -> ClefSpec {
    measure.events.reduce(clef) { clef, event in
        if case .clefChange(let c) = event { return c }
        return clef
    }
}

/// Total horizontal space reserved before the first measure of a system.
///
/// Mirrors the `startWidth` calculation in `VerticalLayoutEngine` so that the
/// `LineBreaker` and `Justifier` can account for it when packing and stretching measures.
///
/// - Parameter keyChange: Non-nil where a body `K:` lands on the system's first measure and
///   the head therefore draws the *change* — cancelling naturals included — rather than the
///   plain signature (#134).  It supersedes `keySignature`, which is the key the change
///   arrives at and so would draw only half of it.
func systemHeaderWidth(
    clef: ClefSpec,
    keySignature: KeySignature?,
    meter: Meter?,
    metadata: BravuraMetadata,
    staffSize: Double,
    keyChange: KeyChange? = nil
) -> Double {
    let clefW    = clefHeaderWidth(for: clef, metadata: metadata, staffSize: staffSize)
    let timeSigW = meter.map { timeSignatureWidth(for: $0, metadata: metadata, staffSize: staffSize) } ?? 0
    // When no time signature follows, use noteheadWidth as the key-sig trailing gap —
    // matching the same logic in VerticalLayoutEngine.
    let keySigTrailing: Double? = timeSigW > 0 ? nil : {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * staffSize } ?? staffSize * 1.2
    }()
    let keySigW = headerKeySignatureWidth(keySignature: keySignature, keyChange: keyChange,
                                          clef: clef, metadata: metadata, staffSize: staffSize,
                                          trailingGap: keySigTrailing)
    return clefW + keySigW + timeSigW
}

/// The width of the key signature run a staff head draws — the change where one lands on the
/// system's first measure, the plain signature otherwise, and zero where the staff carries
/// neither.  One function so the breaker, the justifier, the layout engine and the emitter
/// cannot disagree about how much space the head's accidentals take.
func headerKeySignatureWidth(keySignature: KeySignature?, keyChange: KeyChange?,
                             clef: ClefSpec, metadata: BravuraMetadata, staffSize: Double,
                             trailingGap: Double? = nil) -> Double {
    if let change = keyChange {
        return keyChangeWidth(for: change, metadata: metadata, staffSize: staffSize,
                              trailingGap: trailingGap)
    }
    return keySignature.map {
        keySignatureWidth(for: $0, clef: clef, metadata: metadata, staffSize: staffSize,
                          trailingGap: trailingGap)
    } ?? 0
}
