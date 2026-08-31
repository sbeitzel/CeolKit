import Foundation
import CeolKitModel

/// Which of its two neighbouring staves each part of a **floating** voice is drawn on
/// (ABC v2.2 §11.1, `%%score {RH *M| LH}`).
///
/// §11.1 says only that "the software should automatically determine, for each note of the
/// voice, whether it should be printed on the preceding staff or on the following staff".
/// It states no rule, so this is ours, and `EXTENSIONS.md` says so to the reader.  The three
/// decisions it is made of:
///
/// **A split pitch, not a range.**  Everything at or above the split goes to the staff above,
/// everything below it to the staff below.  Where the voice states `V:` `middle=` that pitch
/// *is* the split; otherwise it is the diatonic midpoint between the bottom line of the staff
/// above and the top line of the staff below — middle C for the treble-over-bass grand staff
/// the directive was invented for.
///
/// **The atom, not the note, is what is assigned.**  A beam, a tuplet, a chord and a tie
/// chain each go somewhere whole: a beam that spanned two staves is not merely ugly, it is
/// undrawable — the emitter draws a beam within one staff and has nowhere to put the other
/// half.  Within an atom the majority of its noteheads decides, and a tie is broken toward
/// the atom's first note, which is the one a reader arrives at it by.
///
/// **Hysteresis, so a melody on the split does not flicker.**  A phrase sitting within
/// ``hysteresis`` steps of the split would otherwise change staff every time it crossed by
/// one step, which is unreadable however defensible each individual choice was.  An atom that
/// close to the split stays where the last one went.
enum FloatingVoiceAssigner {

    /// Which of a floating voice's two neighbours an atom lands on.
    enum Staff: Hashable, Sendable {
        case above
        case below
    }

    /// One run of a floating voice's events that has to be drawn on a single staff.
    ///
    /// Reduced to the only thing the decision turns on — where its noteheads sit — so that
    /// the rule can be tested against a table of pitches with no model behind it.
    struct Atom: Hashable, Sendable {
        /// ``FloatingVoiceAssigner/diatonic(of:)`` of every notehead in the atom, in written
        /// order.  Empty where the atom draws no head at all: a rest, a spacer, a bar of
        /// nothing but directives.
        let steps: [Int]

        init(steps: [Int]) {
            self.steps = steps
        }
    }

    /// How near the split an atom may sit and still be left where the previous one went, in
    /// diatonic steps.
    ///
    /// One step: near enough that the two staves are equally good, so continuity wins.  Two
    /// would hold a voice on the wrong staff across a genuine third.
    static let hysteresis = 1

    /// The staff each of `atoms` is drawn on, parallel to `atoms`.
    ///
    /// - Parameters:
    ///   - atoms: the voice's atoms in playing order.  Order matters: the hysteresis rule
    ///     reads the choice made for the atom before.
    ///   - split: the diatonic index at or above which an atom belongs on the staff above.
    static func assign(atoms: [Atom], split: Int) -> [Staff] {
        var result: [Staff?] = []
        var previous: Staff?

        for atom in atoms {
            guard !atom.steps.isEmpty else {
                // Nothing to weigh.  A rest goes where the music around it went — and where
                // nothing has gone yet, it waits for the first atom that decides.
                result.append(previous)
                continue
            }
            let staff = decide(atom, split: split, previous: previous)
            result.append(staff)
            previous = staff
        }

        // Leading rests, resolved backwards: they belong to the phrase they introduce.
        let first = result.compactMap { $0 }.first ?? .above
        return result.map { $0 ?? first }
    }

    /// The staff one atom lands on, given where the atom before it went.
    private static func decide(_ atom: Atom, split: Int, previous: Staff?) -> Staff {
        // Hysteresis is asked first: an atom straddling the split has a majority like any
        // other, and it is exactly that majority which would flicker.
        let mean = Double(atom.steps.reduce(0, +)) / Double(atom.steps.count)
        if let previous, abs(mean - Double(split)) <= Double(hysteresis) { return previous }

        let above = atom.steps.filter { $0 >= split }.count
        let below = atom.steps.count - above
        if above != below { return above > below ? .above : .below }
        return atom.steps[0] >= split ? .above : .below
    }

    // MARK: - The split

    /// One per diatonic step, rising, with C0 at zero.
    ///
    /// Absolute rather than relative to a staff, because the two staves a floating voice sits
    /// between need not read pitch the same way: the split is a pitch, and the clefs are what
    /// turn it into a position on either staff.
    static func diatonic(of pitch: Pitch) -> Int {
        pitch.octave * 7 + pitch.step.rawValue
    }

    /// The split for a voice floating between two staves: what it said with `middle=`, or the
    /// midpoint between the staves where it said nothing.
    static func split(middle: Pitch?, above: ClefSpec, below: ClefSpec) -> Int {
        middle.map(diatonic(of:)) ?? defaultSplit(above: above, below: below)
    }

    /// The diatonic midpoint between the bottom line of the staff above and the top line of
    /// the staff below.
    ///
    /// Treble over bass — the pairing §11.1's own example uses — gives E4 and A3, whose
    /// midpoint is middle C: the note a pianist's hands already divide at.  Any other pair of
    /// clefs gets the same reasoning applied to it rather than a special case.
    ///
    /// The gap between the two staves is what makes this a *midpoint* rather than a boundary:
    /// a note in it is equally far from both, and could as well be drawn on either.
    static func defaultSplit(above: ClefSpec, below: ClefSpec) -> Int {
        let low  = bottomLine(of: above.clef)
        let high = bottomLine(of: below.clef) + 8   // five lines, two diatonic steps apart
        // Rounded down, so an odd gap resolves toward the lower staff — the one whose top
        // line is nearer the boundary in that case.
        return (low + high) / 2
    }

    /// The written pitch on the bottom line of a staff carrying `clef`, as a diatonic index.
    ///
    /// `octaveShift` is deliberately not applied: `clef=treble+8` sounds an octave up but is
    /// *written* exactly where a treble clef is, and this is a question about where the ink
    /// goes.
    private static func bottomLine(of clef: Clef) -> Int {
        // Each staff line is two diatonic steps above the one below it, so a clef is fixed by
        // the pitch it names and the line it names it on.
        func line(_ pitch: Int, _ number: Int) -> Int { pitch - 2 * (number - 1) }
        let g4 = 4 * 7 + 4      // G4, what a G clef names
        let f3 = 3 * 7 + 3      // F3, what an F clef names
        let c4 = 4 * 7 + 0      // C4, what a C clef names
        switch clef {
        case .treble:                    return line(g4, 2)
        case .bass:                      return line(f3, 4)
        case .baritone:                  return line(f3, 3)
        case .soprano:                   return line(c4, 1)
        case .mezzoSoprano:              return line(c4, 2)
        case .alto:                      return line(c4, 3)
        case .tenor:                     return line(c4, 4)
        // Neither names a pitch.  A staff that does not say where its notes sit is read the
        // way an unmarked staff is read, which is as a treble staff.
        case .percussion, .none:         return line(g4, 2)
        }
    }
}
