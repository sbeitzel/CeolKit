import CeolKitModel

extension Pitch {
    /// One per diatonic step, rising, with C0 at zero.
    ///
    /// Absolute rather than relative to a staff: which line or space a pitch is drawn on is
    /// for a clef to say, and ``ClefSpec/staffPosition(of:)`` is where it says it.
    var diatonicIndex: Int { octave * 7 + step.rawValue }
}

extension Clef {
    /// The written pitch on the bottom line of a staff carrying this clef, as a
    /// ``CeolKitModel/Pitch/diatonicIndex``.
    ///
    /// Each staff line is two diatonic steps above the one below it, so a clef is fixed by
    /// the pitch it names and the line it names it on.  These are abcm2ps's own answers: its
    /// `set_pitch` shifts every note of a staff by the clef's type and line, which comes to
    /// the same thing.
    var bottomLine: Int {
        func line(_ pitch: Int, _ number: Int) -> Int { pitch - 2 * (number - 1) }
        let g4 = 4 * 7 + 4      // G4, what a G clef names
        let f3 = 3 * 7 + 3      // F3, what an F clef names
        let c4 = 4 * 7 + 0      // C4, what a C clef names
        switch self {
        case .treble:                    return line(g4, 2)
        case .bass:                      return line(f3, 4)
        case .baritone:                  return line(f3, 3)
        case .soprano:                   return line(c4, 1)
        case .mezzoSoprano:              return line(c4, 2)
        case .alto:                      return line(c4, 3)
        case .tenor:                     return line(c4, 4)
        // Neither names a pitch.  A staff that does not say where its notes sit is read the
        // way an unmarked staff is read, which is as a treble staff — as abcm2ps reads both.
        case .percussion, .none:         return line(g4, 2)
        }
    }
}

extension ClefSpec {
    /// Which line or space `pitch` is drawn on, on a staff carrying this clef: one per
    /// diatonic step, rising, zero on the bottom line and eight on the top (issue #222).
    ///
    /// `octaveShift` is deliberately not applied.  `clef=treble-8` sounds an octave down but
    /// is *written* exactly where a treble clef is — the 8 is the only difference on the
    /// page, and abcm2ps moves no note for it.
    func staffPosition(of pitch: Pitch) -> Int {
        pitch.diatonicIndex - clef.bottomLine
    }

    static let treble = ClefSpec(clef: .treble, octaveShift: 0)
}
