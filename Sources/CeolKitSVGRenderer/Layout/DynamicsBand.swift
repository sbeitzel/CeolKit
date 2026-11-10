import CeolKitModel

/// Dynamics and hairpins (issue #264), set as abcm2ps sets them (`d_pf`, `d_cresc`,
/// `draw_deco_staff`).
///
/// They stand on a band of their own, beyond everything else on their side of the staff:
/// the notes, the marks on them, and the chord symbols and annotations.  Under the staff
/// by default; over it for a voice that has lyrics anywhere in the tune, so they keep out
/// of the words (`up_p`); and on a shared staff over it for every part but the one stemmed
/// down, which sets them under it.  With abcm2ps's `%%dynalign` (its default) every
/// dynamic and hairpin on one side of a staff line stands on one line, as far out as the
/// one that has to go farthest.
///
/// Distances are in staff spaces.
enum DynamicsBand {

    /// From the band's inner edge to its centre line, on which a hairpin's middle runs and
    /// a dynamic's letters sit centred: abcm2ps's 9 of its 18 points.
    static let centre = 1.5
    /// The whole band, inner edge to outer: abcm2ps's 18 points.
    static let height = 3.0
    /// How far a dynamic's baseline sits beyond the centre line, toward the bottom of the
    /// page: about half Bravura's x-height, so the letters centre on it.
    static let baselineOffset = 0.55

    /// A hairpin's opening, and its narrower opening where it runs on from (a crescendo) or
    /// into (a diminuendo) another system: abcm2ps's 8 and 3.6 points.
    static let opening = 4.0 / 3.0
    static let continuedOpening = 0.6
    /// Bravura's `engravingDefaults.hairpinThickness`.
    static let thickness = 0.16
    /// From the start note's centre to the hairpin, from the hairpin to the end note's
    /// centre, and between a hairpin and a dynamic on the same note: abcm2ps's 3, 4 and 4
    /// points.
    static let startInset = 0.5
    static let endInset = 2.0 / 3.0
    static let dynamicGap = 2.0 / 3.0
    /// abcm2ps draws none shorter than 20 points, widening a shorter one about its middle.
    static let shortest = 20.0 / 6.0

    enum Hairpin: Equatable {
        case crescendo, diminuendo
    }

    /// The glyph `decoration` draws, where it is a dynamic.
    static func glyph(for decoration: Decoration) -> SMuFLGlyph? {
        switch decoration {
        case .ppp: return .dynamicPPP
        case .pp:  return .dynamicPP
        case .p:   return .dynamicPiano
        case .mp:  return .dynamicMP
        case .mf:  return .dynamicMF
        case .f:   return .dynamicForte
        case .ff:  return .dynamicFF
        case .fff: return .dynamicFFF
        case .sfz: return .dynamicSforzato
        default:   return nil
        }
    }

    static func starts(in decorations: [Decoration]) -> [Hairpin] {
        decorations.compactMap {
            switch $0 {
            case .crescendoStart:   return .crescendo
            case .decrescendoStart: return .diminuendo
            default:                return nil
            }
        }
    }

    static func ends(in decorations: [Decoration]) -> [Hairpin] {
        decorations.compactMap {
            switch $0 {
            case .crescendoEnd:   return .crescendo
            case .decrescendoEnd: return .diminuendo
            default:              return nil
            }
        }
    }

    /// Whether `decorations` puts anything on the band.
    static func touches(_ decorations: [Decoration]) -> Bool {
        decorations.contains { glyph(for: $0) != nil }
            || !starts(in: decorations).isEmpty || !ends(in: decorations).isEmpty
    }

    /// Updates the hairpins a part has `open` for one note's `decorations`: an end closes the latest open hairpin of its kind, as abcm2ps pairs a long
    /// decoration's end with its start.
    static func apply(_ decorations: [Decoration], to open: inout [Hairpin]) {
        for end in ends(in: decorations) {
            if let i = open.lastIndex(of: end) { open.remove(at: i) }
        }
        open += starts(in: decorations)
    }

    /// For each system group of a tune and each staff of it, the hairpins each voice has
    /// open as the group begins — one left open at a line break carries on into the next
    /// system, as a tie does, and the band has to be there for it.
    static func openAtStart(of groups: [JustifiedSystemGroup]) -> [[[Int: [Hairpin]]]] {
        var open: [Int: [Int: [Hairpin]]] = [:]   // staff → voice → hairpins
        var result: [[[Int: [Hairpin]]]] = []
        for group in groups {
            result.append(group.staves.indices.map { staff in
                (open[staff] ?? [:]).filter { !$0.value.isEmpty }
            })
            for (staff, system) in group.staves.enumerated() {
                for measure in system.measures {
                    let events = measure.source.measure.events
                    for (index, event) in events.enumerated() {
                        let voice = index < measure.eventVoiceIndices.count
                            ? measure.eventVoiceIndices[index] : 0
                        apply(decorations(of: event), to: &open[staff, default: [:]][voice, default: []])
                    }
                }
            }
        }
        return result
    }

    /// For each staff of a tune's groups, whether its voice has lyrics anywhere in the tune:
    /// abcm2ps's `have_ly`, which moves a voice's dynamics over the staff.
    static func staffHasLyrics(in groups: [JustifiedSystemGroup]) -> Set<Int> {
        var staves: Set<Int> = []
        for group in groups {
            for (staff, system) in group.staves.enumerated() where !staves.contains(staff) {
                let sung = system.measures.contains { measure in
                    measure.source.measure.events.contains { event in
                        switch event {
                        case .note(let n):  return n.lyrics.contains { $0 != nil }
                        case .chord(let c): return c.lyrics.contains { $0 != nil }
                        default:            return false
                        }
                    }
                }
                if sung { staves.insert(staff) }
            }
        }
        return staves
    }

    /// The decorations of a note or chord, the chord's own and its notes' alike.
    static func decorations(of event: Event) -> [Decoration] {
        switch event {
        case .note(let n):  return n.decorations
        case .chord(let c): return c.decorations + c.notes.flatMap(\.decorations)
        case .tuplet(let t): return t.events.flatMap(decorations(of:))
        default:            return []
        }
    }
}
