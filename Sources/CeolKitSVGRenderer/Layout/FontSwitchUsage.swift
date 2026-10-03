import CeolKitModel

/// Finds the font switches a tune's text makes to a `%%setfont-n` no directive set
/// (ABC v2.2 §11.4.2; issue #204).
///
/// Such a switch still takes effect: abcm2ps documents every `%%setfont-n` as "(none) 12",
/// and CeolKit sets the run in the face of the string it is in at that size.  It is
/// warned about because the author almost certainly meant a face, and the directive that
/// would have named it is missing or misspelt.
enum FontSwitchUsage {
    /// The first place each switch in `fonts` is written in `tune`'s printed text.
    static func firstUses(of fonts: Set<FontSwitch.Font>, in tune: Tune)
        -> [(font: FontSwitch.Font, source: SourceRange)] {
        guard !fonts.isEmpty else { return [] }
        var found: [FontSwitch.Font: SourceRange] = [:]
        func scan(_ text: String, at source: SourceRange) {
            for font in FontSwitch.fonts(switchedTo: text)
            where fonts.contains(font) && found[font] == nil {
                found[font] = source
            }
        }
        func scan(_ text: TextString?) {
            if let text { scan(text.value, at: text.source) }
        }

        tune.titles.forEach(scan)
        tune.metadata.composer.forEach(scan)
        tune.metadata.rhythm.forEach(scan)
        for origin in tune.metadata.origin { scan(origin, at: tune.source) }
        scan(tune.tempo?.prelude)
        scan(tune.tempo?.postlude)
        tune.words.forEach(scan)

        func scan(_ events: [Event]) {
            for event in events {
                switch event {
                case .note(let n):
                    scan(n.chordSymbol, n.annotations, n.lyrics, at: n.source)
                case .chord(let c):
                    scan(c.chordSymbol, c.annotations, c.lyrics, at: c.source)
                case .tuplet(let t):
                    scan(t.events)
                case .tempoChange(let tempo):
                    scan(tempo.prelude)
                    scan(tempo.postlude)
                default:
                    break
                }
            }
        }
        func scan(_ chordSymbol: ChordSymbol?, _ annotations: [Annotation],
                  _ lyrics: [LyricSyllable?], at source: SourceRange) {
            if let chordSymbol { scan(chordSymbol.raw, at: chordSymbol.source) }
            annotations.forEach { scan($0.text) }
            for case .text(let text, _)? in lyrics {
                // A syllable has no place of its own in the source; its note stands in.
                scan(text.value, at: source)
            }
        }
        for voice in tune.voices {
            for staff in voice.staves {
                for measure in staff.measures { scan(measure.events) }
            }
        }
        return found.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}
