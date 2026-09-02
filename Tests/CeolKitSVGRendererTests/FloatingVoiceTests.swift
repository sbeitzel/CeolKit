import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #80: a voice written `*V` between two groups is printed on whichever of the two
/// staves suits each part of it (ABC v2.2 §11.1).
///
/// §11.1 states no rule for choosing, so the rule is ours and `EXTENSIONS.md` documents it.
/// These tests pin the three decisions it is made of — the split, the atom, the hysteresis —
/// against the table the assigner is written as, and then check that the split survives the
/// journey through selection to the page.
@Suite("Floating Voices")
struct FloatingVoiceTests {

    // MARK: - Helpers

    private typealias Assigner = FloatingVoiceAssigner
    private typealias Atom = FloatingVoiceAssigner.Atom

    /// The diatonic index of an ABC pitch name, written the way `middle=` writes it.
    private func step(_ name: String) -> Int {
        var octave = name.first!.isLowercase ? 5 : 4
        for ch in name.dropFirst() { octave += ch == "," ? -1 : 1 }
        let letters: [Character: DiatonicStep] = ["c": .c, "d": .d, "e": .e, "f": .f,
                                                  "g": .g, "a": .a, "b": .b]
        let letter = letters[Character(name.first!.lowercased())]!
        return Assigner.diatonic(of: Pitch(step: letter, alteration: .natural, octave: octave))
    }

    private func atom(_ names: String...) -> Atom {
        Atom(steps: names.map(step))
    }

    private func clef(_ clef: Clef) -> ClefSpec {
        ClefSpec(clef: clef, octaveShift: 0)
    }

    private func select(_ abc: String)
        -> (selection: VoiceSelector.Selection, diagnostics: [Diagnostic]) {
        let tune = CeolKitParser().parse(abc, options: .default).score.tunes[0]
        var diagnostics: [Diagnostic] = []
        let plan = tune.staffPlans.last { $0.effectiveFromStave == 0 }?.plan
        return (VoiceSelector.select(from: tune.voices, plan: plan, into: &diagnostics),
                diagnostics)
    }

    /// The pitches each printed staff of `abc` draws, top to bottom, as diatonic indices.
    ///
    /// Read off the selection rather than the page: the geometry says where the noteheads
    /// are, but only this says which staff carries which note, and that is the whole question.
    private func staffPitches(_ abc: String) -> [[Int]] {
        let selection = select(abc).selection
        return selection.voicesByStaff.map { members in
            members.flatMap { index in
                selection.voices[index].staves.flatMap(\.measures).flatMap(\.events)
                    .flatMap(pitches(of:))
            }
        }
    }

    private func pitches(of event: Event) -> [Int] {
        switch event {
        case .note(let n):   return [Assigner.diatonic(of: n.pitch)]
        case .chord(let c):  return c.notes.map { Assigner.diatonic(of: $0.pitch) }
        case .tuplet(let t): return t.events.flatMap(pitches(of:))
        default:             return []
        }
    }

    /// A grand staff with `M` floating between the hands.
    private func grandStaff(_ melody: String, middle: String = "", plan: String = "{RH *M| LH}")
        -> String {
        """
        X:1
        L:1/8
        %%score \(plan)
        V:RH clef=treble
        V:M\(middle.isEmpty ? "" : " middle=\(middle)")
        V:LH clef=bass
        K:C
        V:RH
        c8|
        V:M
        \(melody)
        V:LH
        C8|
        """
    }

    // MARK: - The split

    @Test("Treble over bass splits at middle C")
    func defaultSplitOfAGrandStaff() {
        #expect(Assigner.defaultSplit(above: clef(.treble), below: clef(.bass)) == step("C"))
    }

    @Test("Other clef pairs get the same reasoning, not a special case")
    func defaultSplitOfOtherClefs() {
        // Alto bottom line F3, tenor top line E4: the midpoint is B3, a fourth below the
        // treble-over-bass answer, because both staves sit lower.
        #expect(Assigner.defaultSplit(above: clef(.alto), below: clef(.tenor)) == step("B,"))
        // Two treble staves: bottom line E4 against top line F5, midpoint B4.
        #expect(Assigner.defaultSplit(above: clef(.treble), below: clef(.treble)) == step("B"))
    }

    @Test("`middle=` is the split where the voice states one")
    func middleOverridesTheDefault() {
        let split = Assigner.split(
            middle: Pitch(step: .b, alteration: .natural, octave: 4),
            above: clef(.treble), below: clef(.bass))
        #expect(split == step("B"))
    }

    @Test("An octave-shifted clef splits where it is written, not where it sounds")
    func octaveShiftDoesNotMoveTheSplit() {
        let plain   = Assigner.defaultSplit(above: clef(.treble), below: clef(.bass))
        let shifted = Assigner.defaultSplit(
            above: ClefSpec(clef: .treble, octaveShift: 8),
            below: ClefSpec(clef: .bass, octaveShift: -8))
        #expect(shifted == plain)
    }

    // MARK: - The rule, as a table

    @Test("A single note goes to the staff its pitch falls on")
    func singleNotes() {
        let split = step("C")
        #expect(Assigner.assign(atoms: [atom("g")], split: split) == [.above])
        #expect(Assigner.assign(atoms: [atom("G,")], split: split) == [.below])
        // The split itself belongs to the staff above: it is the lowest pitch that staff owns.
        #expect(Assigner.assign(atoms: [atom("C")], split: split) == [.above])
    }

    @Test("An atom goes where the majority of its noteheads go")
    func majorityWithinAnAtom() {
        let split = step("C")
        // Three of four above the split; the low note comes along rather than break the beam.
        #expect(Assigner.assign(atoms: [atom("e", "g", "G,", "c")], split: split) == [.above])
        #expect(Assigner.assign(atoms: [atom("E,", "G,", "e", "C,")], split: split) == [.below])
    }

    @Test("A tie within an atom is broken toward its first note")
    func tiesGoToTheFirstNote() {
        let split = step("C")
        #expect(Assigner.assign(atoms: [atom("e", "G,")], split: split) == [.above])
        #expect(Assigner.assign(atoms: [atom("G,", "e")], split: split) == [.below])
    }

    @Test("A melody hovering at the split does not alternate staves")
    func hysteresisHoldsAMelodyStill() {
        let split = step("C")
        // B3 and C4 lie either side of the split by one step each.  Without hysteresis this
        // is .below, .above, .below, .above; with it the phrase stays where it started.
        let atoms = [atom("G,"), atom("B,"), atom("C"), atom("B,"), atom("C")]
        #expect(Assigner.assign(atoms: atoms, split: split)
                == [.below, .below, .below, .below, .below])
    }

    @Test("Hysteresis yields to a real departure from the split")
    func hysteresisYieldsToAClearMove() {
        let split = step("C")
        let atoms = [atom("G,"), atom("B,"), atom("g"), atom("C")]
        #expect(Assigner.assign(atoms: atoms, split: split)
                == [.below, .below, .above, .above])
    }

    @Test("Hysteresis is measured in diatonic steps from the split")
    func hysteresisThreshold() {
        let split = step("C")
        // One step above the split holds; two steps above does not.
        #expect(Assigner.assign(atoms: [atom("G,"), atom("D")], split: split)
                == [.below, .below])
        #expect(Assigner.assign(atoms: [atom("G,"), atom("E")], split: split)
                == [.below, .above])
        #expect(Assigner.hysteresis == 1)
    }

    @Test("The first atom has nothing to hold it, so it goes where its pitch says")
    func firstAtomIgnoresHysteresis() {
        #expect(Assigner.assign(atoms: [atom("B,")], split: step("C")) == [.below])
    }

    @Test("An atom that draws no notehead follows the music around it")
    func restsFollowTheMusic() {
        let split = step("C")
        // A leading rest waits for the phrase it introduces; a rest inside one stays put.
        let atoms = [Atom(steps: []), atom("G,"), Atom(steps: []), atom("g")]
        #expect(Assigner.assign(atoms: atoms, split: split)
                == [.below, .below, .below, .above])
    }

    @Test("A voice of nothing but rests is assigned somewhere rather than trapping")
    func nothingButRests() {
        #expect(Assigner.assign(atoms: [Atom(steps: []), Atom(steps: [])], split: step("C"))
                == [.above, .above])
        #expect(Assigner.assign(atoms: [], split: step("C")).isEmpty)
    }

    // MARK: - Splitting the voice

    @Test("`%%score {RH *M| LH}` places each atom of M on RH or LH by pitch")
    func atomsLandOnTheStaffTheirPitchChooses() {
        let staves = staffPitches(grandStaff("c2 G,2 e2 E,2|"))
        #expect(staves.count == 2)
        #expect(staves[0] == [step("c"), step("c"), step("e")])
        #expect(staves[1] == [step("C"), step("G,"), step("E,")])
    }

    @Test("A beamed run never splits across staves")
    func beamedRunsStayWhole() {
        // `C,EGc` beams as one group and straddles the split: C3 is a seventh below it and
        // the other three are above.  The majority carries the low note upstairs with them,
        // because a beam drawn half on each staff is not something the emitter can draw.
        let staves = staffPitches(grandStaff("C,EGc c'4|"))
        #expect(staves[0] == [step("c"), step("C,"), step("E"), step("G"), step("c"), step("c'")])
        #expect(staves[1] == [step("C")])
    }

    @Test("A tie over a bar line keeps both its notes on one staff")
    func tiedNotesStayWhole() {
        // The tie opens in one bar and closes in the next, which is the only way the two
        // halves of it could be handed to different staves.
        let selection = select(grandStaff("e6 D-|D E,2 C,4|")).selection
        let upper = selection.voices[selection.voicesByStaff[0].last!]
        let lower = selection.voices[selection.voicesByStaff[1].last!]
        func ds(_ voice: Voice) -> Int {
            voice.staves.flatMap(\.measures).flatMap(\.events).flatMap(pitches(of:))
                .filter { $0 == step("D") }.count
        }
        // Both D's on one staff, and neither on the other.
        #expect([ds(upper), ds(lower)].contains(2))
        #expect([ds(upper), ds(lower)].contains(0))
    }

    @Test("A chord is one atom, decided by the majority of its noteheads")
    func chordsAreOneAtom() {
        // G3 is below the split and the other two are well above it; the chord cannot be
        // drawn across two staves, so it goes where its majority goes, whole.
        let staves = staffPitches(grandStaff("[G,ce]8|"))
        #expect(staves[0] == [step("c"), step("G,"), step("c"), step("e")])
        #expect(staves[1] == [step("C")])
    }

    @Test("`V:M middle=B` moves the split, verifiably")
    func middleMovesTheSplit() {
        // With the default split at middle C, `c` is the upper staff's.  `middle=e` puts the
        // split above it, and the same note goes downstairs instead.
        #expect(staffPitches(grandStaff("c8|"))[0].contains(step("c")))
        #expect(staffPitches(grandStaff("c8|", middle: "e"))[1].contains(step("c")))
        // And it reaches the model on the way, so nothing else can be doing the work.
        let tune = CeolKitParser().parse(grandStaff("c8|", middle: "e"), options: .default)
            .score.tunes[0]
        let melody = tune.voices.first { $0.id == .named("M") }
        #expect(melody?.properties.middleNote == Pitch(step: .e, alteration: .natural, octave: 5))
    }

    @Test("The silent half keeps the time, so both halves measure the bar alike")
    func displacedMusicIsPaddedWithInvisibleRests() {
        let selection = select(grandStaff("C,2 c2 C,4|")).selection
        // Staff 0's tenants are RH and the upper half of M; the half's own bar is the one to
        // look at.  Only what sounds is examined: the whitespace spacers the source is
        // written with take no time and claim no width.
        let half = selection.voices[selection.voicesByStaff[0].last!]
        let sounding = half.staves[0].measures[0].events.filter {
            if case .spacer = $0 { return false }
            return true
        }
        // A rest for the first two eighths, then the note that stayed.  The last four
        // eighths went downstairs and get no rest at all: silence at the end of a bar moves
        // nothing that follows it.
        #expect(sounding.count == 2)
        guard case .rest(let rest) = sounding.first else {
            Issue.record("expected the displaced music to be stood in for by a rest")
            return
        }
        #expect(rest.kind == .invisible)
        #expect(rest.duration == Fraction(numerator: 2, denominator: 1))
        if case .note = sounding.last {} else { Issue.record("expected the kept note to follow") }
    }

    @Test("Each half stems away from the staff its music came from")
    func halvesOpposeTheirHosts() {
        let selection = select(grandStaff("c4 C,4|")).selection
        let upper = selection.voices[selection.voicesByStaff[0].last!]
        let lower = selection.voices[selection.voicesByStaff[1].last!]
        #expect(upper.properties.stemDirection == .down)
        #expect(lower.properties.stemDirection == .up)
    }

    @Test("A voice that stated `stem=` keeps its word on both staves")
    func statedStemDirectionSurvivesTheSplit() {
        let abc = grandStaff("c4 C,4|").replacing("V:M\n", with: "V:M stem=up\n")
        let selection = select(abc).selection
        let upper = selection.voices[selection.voicesByStaff[0].last!]
        let lower = selection.voices[selection.voicesByStaff[1].last!]
        #expect(upper.properties.stemDirection == .up)
        #expect(lower.properties.stemDirection == .up)
    }

    // MARK: - End to end

    @Test("A grand staff with a floating voice draws two staves, and every note of it")
    func rendersTwoStaves() throws {
        let score = CeolKitParser().parse(grandStaff("c2 G,2 e2 E,2|"), options: .default).score
        var diagnostics: [Diagnostic] = []
        let pages = try SVGGeometry.pages(from: SVGRenderer().render(score,
                                                                    diagnostics: &diagnostics))
        #expect(pages.flatMap(\.systems).count == 2)
        #expect(diagnostics.filter { $0.code == .staffPlanNotFullyApplied }.isEmpty)
    }

    @Test("A floating voice with no neighbour at all still gets printed")
    func noNeighbourStillPrints() {
        let result = select("""
        X:1
        L:1/4
        %%score {*M}
        V:M
        K:C
        V:M
        CDEF|
        """)
        #expect(result.selection.voices.map(\.id) == [.named("M")])
        #expect(result.selection.staffCount == 1)

        let warnings = result.diagnostics.filter { $0.code == .staffPlanNotFullyApplied }
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.contains("no neighbouring staff at all") == true)
    }

    @Test("A floating voice with only one neighbour prints on it rather than vanishing")
    func oneNeighbourStillPrints() {
        // `*M` at the bottom of the plan has a staff above it and none below.
        let staves = staffPitches(grandStaff("c4 C,4|", plan: "{RH LH| *M}"))
        #expect(staves.count == 2)
        #expect(staves[1] == [step("C"), step("c"), step("C,")])
    }
}
