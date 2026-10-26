import CeolKitModel

/// Formats a `Tempo` value as a human-readable annotation string.
///
/// Examples, `♩` standing for SMuFL's `metNoteQuarterUp`:
///   - `beats: [1/4], bpm: 120`              → `"♩ = 120"`
///   - `prelude: "Andante", beats: [1/4], bpm: 110` → `"Andante ♩ = 110"`
///   - `prelude: "80 bpm", beats: []`        → `"80 bpm"`
///
/// A font switch in the prelude or postlude (§11.4.2) is closed at its end, so it sets
/// only the text it was written in and never the metronome mark (issue #204).
///
/// The beat's note is written in SMuFL's metronome glyphs, which ``TextStyle`` sets in
/// Bravura whatever face the tempo text is in: a text face has the quarter and eighth at
/// best, never the half or the whole (issue #230).
func tempoAnnotationText(_ tempo: Tempo) -> String {
    var parts: [String] = []
    func closed(_ text: String) -> String {
        FontSwitch.runs(in: text).endFont == 0 ? text : text + "$0"
    }
    if let pre = tempo.prelude?.value, !pre.isEmpty {
        parts.append(closed(pre))
    }
    if !tempo.beats.isEmpty, tempo.bpm > 0 {
        let beatStr = tempo.beats.map { tempoNoteBeatSymbol(for: $0) }.joined(separator: "+")
        let bpmInt = Int(tempo.bpm.rounded())
        parts.append("\(beatStr) = \(bpmInt)")
    } else if tempo.bpm > 0, tempo.prelude == nil {
        let bpmInt = Int(tempo.bpm.rounded())
        parts.append("= \(bpmInt)")
    }
    if let post = tempo.postlude?.value, !post.isEmpty {
        parts.append(closed(post))
    }
    return parts.joined(separator: " ")
}

private func tempoNoteBeatSymbol(for beat: Fraction) -> String {
    let whole = "\u{ECA2}"      // metNoteWhole
    let half = "\u{ECA3}"       // metNoteHalfUp
    let quarter = "\u{ECA5}"    // metNoteQuarterUp
    let eighth = "\u{ECA7}"     // metNote8thUp
    // metAugmentationDot, after a hair space so it clears the stem and flag.
    let dot = "\u{200A}\u{ECB7}"
    switch (beat.numerator, beat.denominator) {
    case (1, 1): return whole
    case (1, 2): return half
    case (3, 4): return half + dot
    case (1, 4): return quarter
    case (3, 8): return quarter + dot
    case (1, 8): return eighth
    case (3, 16): return eighth + dot
    default: return "\(beat.numerator)/\(beat.denominator)"
    }
}
