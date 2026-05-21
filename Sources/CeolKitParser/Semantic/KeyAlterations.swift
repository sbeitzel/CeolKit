import CeolKitModel

/// Computes the diatonic-step → alteration map for a given key signature using the circle of fifths.
/// This is the baseline used by AccidentalScope before any in-bar overrides are applied.
func keyAlterations(for key: KeySignature) -> [DiatonicStep: Alteration] {
    switch key.mode {
    case .none:
        // K:none — no key signature, all naturals
        return applyModifications([:], modifications: key.modifications)
    case .highlandPipes:
        // K:HP — F# and C# always, regardless of tonic
        let base: [DiatonicStep: Alteration] = [.f: .sharp, .c: .sharp]
        return applyModifications(base, modifications: key.modifications)
    case .highlandPipesNoSignature:
        return applyModifications([:], modifications: key.modifications)
    default:
        break
    }

    guard let tonic = key.tonic else {
        return applyModifications([:], modifications: key.modifications)
    }

    // Number of fifths for each diatonic step in major mode relative to C major (0 fifths)
    let tonicFifths: [DiatonicStep: Int] = [.c: 0, .d: 2, .e: 4, .f: -1, .g: 1, .a: 3, .b: 5]
    // Modal offset: how many fifths to add to the major-mode count for the same tonic
    let modeOffset: [Mode: Int] = [
        .major: 0, .ionian: 0,
        .dorian: -2, .phrygian: -4, .lydian: 1,
        .mixolydian: -1, .aeolian: -3, .minor: -3,
        .locrian: -5
    ]

    let baseFifths = tonicFifths[tonic.step] ?? 0
    let alterationFifths = tonic.alteration.denominator == 1 ? tonic.alteration.numerator * 7 : 0
    let offset = modeOffset[key.mode] ?? 0
    let totalFifths = baseFifths + alterationFifths + offset

    let base = buildKeyFromFifths(totalFifths)
    return applyModifications(base, modifications: key.modifications)
}

private func buildKeyFromFifths(_ fifths: Int) -> [DiatonicStep: Alteration] {
    let sharpsOrder: [DiatonicStep] = [.f, .c, .g, .d, .a, .e, .b]
    let flatsOrder:  [DiatonicStep] = [.b, .e, .a, .d, .g, .c, .f]
    var result: [DiatonicStep: Alteration] = [:]
    if fifths > 0 {
        for i in 0..<min(fifths, sharpsOrder.count) {
            result[sharpsOrder[i]] = .sharp
        }
    } else if fifths < 0 {
        for i in 0..<min(-fifths, flatsOrder.count) {
            result[flatsOrder[i]] = .flat
        }
    }
    return result
}

private func applyModifications(
    _ base: [DiatonicStep: Alteration],
    modifications: [KeyModification]
) -> [DiatonicStep: Alteration] {
    var result = base
    for mod in modifications {
        if mod.alteration == .natural {
            result.removeValue(forKey: mod.step)
        } else {
            result[mod.step] = mod.alteration
        }
    }
    return result
}

