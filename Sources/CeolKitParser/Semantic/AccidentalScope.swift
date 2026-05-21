import CeolKitModel

/// Tracks accidental state within a single bar.
///
/// The key signature provides the baseline alteration for each step (octave-independent).
/// Within a bar, explicit written accidentals override the key signature for subsequent
/// notes at the same pitch level (step + octave), per ABC spec §4.3.
struct AccidentalScope {
    let keyAlterations: [DiatonicStep: Alteration]
    private var barMemory: [(step: DiatonicStep, octave: Int, alteration: Alteration)] = []

    init(keyAlterations: [DiatonicStep: Alteration]) {
        self.keyAlterations = keyAlterations
    }

    /// Returns the effective alteration for a note. Checks bar memory first, then key signature.
    func resolve(step: DiatonicStep, octave: Int) -> Alteration {
        for entry in barMemory.reversed() where entry.step == step && entry.octave == octave {
            return entry.alteration
        }
        return keyAlterations[step] ?? .natural
    }

    /// Records an explicitly written accidental into bar memory.
    mutating func record(step: DiatonicStep, octave: Int, alteration: Alteration) {
        barMemory.append((step, octave, alteration))
    }

    /// Clears in-bar memory at each bar line. Key signature remains unchanged.
    mutating func resetBar() {
        barMemory = []
    }
}
