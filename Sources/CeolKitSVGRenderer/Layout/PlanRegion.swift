import CeolKitModel

/// Pass 1⅛: cuts a tune into the runs of staves that one `%%score` / `%%staves` plan governs.
///
/// §11.1: a plan written in the tune body "resets the music generator, so that voices may
/// appear and disappear for some period of time".  That makes the set of printed voices — and
/// so the number of staves in a system — a property of *where* you are in the tune, not of the
/// tune.  Everything downstream of `VoiceSelector` assumes one staff count for everything it
/// is handed, so the tune is handed over one region at a time and the results concatenated.
///
/// A region boundary is therefore always a system break: the staves of a system are laid out
/// together, so the plan cannot change part-way through one.  The parser has already snapped
/// each plan back to the start of the stave enclosing it (see ``StaffPlanChange``), which is
/// what makes a region a whole number of staves.
///
/// **Regions are cut by stave index**, which is the same numbering ``VoiceAligner`` aligns on:
/// stave *k* of one voice is stave *k* of every other.  A source that gives a voice no line at
/// all in some line-set breaks that assumption before a plan is involved — the voice's later
/// staves all shift up one — and a region cut then lands in the wrong place for it, exactly as
/// the aligner's padding already does.  Write every voice a line per system and the numbering
/// holds.
struct PlanRegion {
    /// The plan governing this region, or `nil` for the opening region of a tune whose plans
    /// all start later — that stretch is laid out exactly as a tune with no plan at all.
    let plan: StaffPlan?
    /// Every voice of the tune, with its staves cut down to the ones this region covers.  A
    /// voice with nothing to say here is empty, and so is not printed; it resumes on its own
    /// staff in the next region that has music for it.
    let voices: [Voice]
    /// The staves this region covers, as indices into the tune's stave numbering.  Carried for
    /// diagnostics and tests; the layout works from ``voices``.
    let staves: Range<Int>
}

enum PlanRegions {

    /// Segments `tune` into maximal runs of staves governed by one plan, in source order.
    ///
    /// Always returns at least one region, so a tune with no plan — the overwhelming majority —
    /// takes exactly the path it did before regions existed: one region, the tune's own voices,
    /// no slicing.
    static func segment(_ tune: Tune) -> [PlanRegion] {
        let staveCount = tune.voices.reduce(0) { max($0, $1.staves.count) }

        // Two changes can share a stave — a file-preamble plan and a tune-header plan both
        // govern from stave 0 — and the last one written wins, as it does for every other
        // directive.  A plan starting past the end of the music governs nothing and is dropped.
        var planByStave: [Int: StaffPlan] = [:]
        for change in tune.staffPlans where change.effectiveFromStave < staveCount {
            planByStave[change.effectiveFromStave] = change.plan
        }

        // No music, or every plan governs from the very first stave: one region over the whole
        // tune, and no `Voice` is rebuilt.
        guard let boundaries = boundaries(planByStave.keys, staveCount: staveCount) else {
            let plan = tune.staffPlans.last { $0.effectiveFromStave == 0 }?.plan
            return [PlanRegion(plan: plan, voices: tune.voices, staves: 0..<staveCount)]
        }

        return boundaries.indices.map { index in
            let start = boundaries[index]
            let end = index + 1 < boundaries.count ? boundaries[index + 1] : staveCount
            let range = start..<end
            return PlanRegion(
                plan: planByStave[start],
                voices: tune.voices.map { $0.covering(range) },
                staves: range
            )
        }
    }

    /// The stave indices each region starts at, or `nil` when there is only one region.
    ///
    /// The opening region always starts at stave 0, whether or not a plan does.
    private static func boundaries(_ starts: some Collection<Int>, staveCount: Int) -> [Int]? {
        guard staveCount > 0 else { return nil }
        var all = Set(starts)
        all.insert(0)
        guard all.count > 1 else { return nil }
        return all.sorted()
    }
}

private extension Voice {
    /// The same voice holding only the staves in `range`.
    func covering(_ range: Range<Int>) -> Voice {
        Voice(id: id, properties: properties, key: key, unitNoteLength: unitNoteLength,
              staves: Array(staves[range.clamped(to: staves.indices)]),
              directives: directives, source: source)
    }
}
