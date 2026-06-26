import CeolKitModel

/// Formats a `Tempo` value as a human-readable annotation string.
///
/// Examples:
///   - `beats: [1/4], bpm: 120`              → `"♩ = 120"`
///   - `prelude: "Andante", beats: [1/4], bpm: 110` → `"Andante ♩ = 110"`
///   - `prelude: "80 bpm", beats: []`        → `"80 bpm"`
func tempoAnnotationText(_ tempo: Tempo) -> String {
    var parts: [String] = []
    if let pre = tempo.prelude?.value, !pre.isEmpty {
        parts.append(pre)
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
        parts.append(post)
    }
    return parts.joined(separator: " ")
}

private func tempoNoteBeatSymbol(for beat: Fraction) -> String {
    switch (beat.numerator, beat.denominator) {
    case (1, 1): return "𝅝"    // whole note
    case (1, 2): return "𝅗𝅥"   // half note (two codepoints)
    case (3, 4): return "𝅗𝅥."  // dotted half
    case (1, 4): return "♩"
    case (3, 8): return "♩."
    case (1, 8): return "♪"
    case (3, 16): return "♪."
    default: return "\(beat.numerator)/\(beat.denominator)"
    }
}
