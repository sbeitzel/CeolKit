import CeolKitModel

/// Formats a `Tempo` value as a human-readable annotation string.
///
/// Examples:
///   - `beats: [1/4], bpm: 120`              → `"♩ = 120"`
///   - `prelude: "Andante", beats: [1/4], bpm: 110` → `"Andante ♩ = 110"`
///   - `prelude: "80 bpm", beats: []`        → `"80 bpm"`
///
/// A font switch in the prelude or postlude (§11.4.2) is closed at its end, so it sets
/// only the text it was written in and never the metronome mark (issue #204).
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
