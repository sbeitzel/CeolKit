import CeolKitModel

/// Turns the `&` overlays of ABC v2.2 §7.4 into the ordinary voices the rest of the layout
/// draws, each a further tenant of the staff its voice is already on.
///
/// Nothing downstream of here knows what an overlay is, and it does not have to.  A staff
/// already carries more than one voice — that is what a `%%score ( … )` group is — so an
/// overlay becomes a second (or third) tenant of the one staff, and the merge onto a common
/// onset grid (#76), the opposed stems (#77), the per-voice beams, ties and slurs (#78) and
/// the displaced unisons (#79) all apply to it unchanged.  It is the same trick
/// ``FloatingVoiceSplitter`` plays for a floating voice, from the other direction.
///
/// **A layer keeps its voice's id, key, unit note length and properties.**  It *is* that
/// voice — §7.4 calls it a temporary voice of the same music — so a diagnostic that names it
/// should name the voice the reader wrote, and its notes must be read against the same `L:`
/// and drawn under the same clef.  Its stem direction is left as the voice stated it, `.auto`
/// included: a shared staff opposes its tenants by position rather than by pitch (#77), and
/// an overlay is exactly a tenant below the voice it overlays.
///
/// **A layer is present on every stave of its voice**, empty where it is silent, so its
/// position in the staff is the same from one system to the next.  That is the invariant
/// ``VoiceOverlay`` states, and it is what lets the expansion be this simple: the layer count
/// is a property of the voice, not of the line.
enum OverlayExpander {

    /// Expands every voice of one staff in place: each voice, then its overlays, outermost
    /// first, so the voice itself stays the staff's lead and the layers stack under it.
    static func expand(_ voices: [Voice]) -> [Voice] {
        voices.flatMap { voice -> [Voice] in
            let layers = voice.staves.map(\.overlays.count).max() ?? 0
            guard layers > 0 else { return [voice] }
            return [stripped(voice)] + (0..<layers).map { layer(voice, at: $0) }
        }
    }

    /// The voice without its overlays — the same music, drawn as it always was.
    private static func stripped(_ voice: Voice) -> Voice {
        rebuilt(voice, staves: voice.staves.map { Staff(measures: $0.measures, overlays: []) })
    }

    /// One `&` layer of `voice`, as a voice of its own.
    ///
    /// A stave that does not reach this layer contributes bars with no music rather than no
    /// bars: ``VoiceAligner`` aligns voices stave by stave, and a layer short of a stave would
    /// be padded and warned about for music the source never claimed to have written.
    private static func layer(_ voice: Voice, at index: Int) -> Voice {
        rebuilt(voice, staves: voice.staves.map { stave in
            guard index < stave.overlays.count else {
                return Staff(measures: stave.measures.map(silent(like:)), overlays: [])
            }
            return Staff(measures: stave.overlays[index].measures, overlays: [])
        })
    }

    /// A bar the layer says nothing in, keeping the bar lines of the one it stands beside so
    /// the two staves still measure the line the same way.
    private static func silent(like measure: Measure) -> Measure {
        Measure(openingBar: measure.openingBar, events: [], closingBar: measure.closingBar,
                endingNumber: nil, source: measure.source, meter: measure.meter,
                unitNoteLength: measure.unitNoteLength)
    }

    private static func rebuilt(_ voice: Voice, staves: [Staff]) -> Voice {
        Voice(id: voice.id, properties: voice.properties, key: voice.key,
              unitNoteLength: voice.unitNoteLength, staves: staves,
              directives: voice.directives, source: voice.source)
    }
}
