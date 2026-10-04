import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #223: a `K:` may name a clef and no key.  §3.1.14 allows an empty key, which the
/// options can follow, and §4.6 lets a named clef drop its `clef=` — so `K:bass` is
/// `K:clef=bass`, and the standard writes `[K:clef=bass]` part way through a tune itself.
///
/// abcm2ps reads such a field as changing only what it states: across `K:D` … `K:bass` the
/// staff goes to the bass clef and keeps D major's two sharps.
@Suite("K: with a clef and no key")
struct KeyWithoutTonicTests {

    private static let treble = ClefSpec(clef: .treble, octaveShift: 0)
    private static let bass = ClefSpec(clef: .bass, octaveShift: 0)

    private func parseKey(_ payload: String) -> (KeySignature, [Diagnostic]) {
        KeyFieldParser.parse(payload: payload, source: .emptySourceRange)
    }

    private func parse(_ body: String) -> ParseResult {
        CeolKitParser().parse("""
        X:1
        T:Test
        M:4/4
        L:1/4
        \(body)
        """, options: .default)
    }

    private func measures(_ result: ParseResult) -> [Measure] {
        result.score.tunes[0].voices[0].staves.flatMap(\.measures)
    }

    /// The clef changes written in `measure`, in order.
    private func clefChanges(_ measure: Measure) -> [ClefSpec] {
        measure.events.compactMap {
            if case .clefChange(let clef) = $0 { return clef }
            return nil
        }
    }

    // MARK: The field parser

    @Test("A clef with no key is read as options, with no key stated",
          arguments: ["clef=bass", "bass", "  bass  "])
    func clefWithoutKey(payload: String) {
        let (key, diagnostics) = parseKey(payload)
        #expect(diagnostics.isEmpty)
        #expect(!key.statesKey)
        #expect(key.statesClef)
        #expect(key.clef == Self.bass)
    }

    @Test("Every option is read on a K: with no key")
    func otherOptionsWithoutKey() {
        let (key, diagnostics) = parseKey("bass octave=-1 stafflines=4")
        #expect(diagnostics.isEmpty)
        #expect(!key.statesKey)
        #expect(key.clef == Self.bass)
        #expect(key.transposition.statesOctave)
        #expect(key.transposition.octave == -1)
        #expect(key.staffProperties.staffLines == 4)
    }

    @Test("An empty K: states neither a key nor a clef, and is not malformed")
    func emptyKey() {
        let (key, diagnostics) = parseKey("")
        #expect(diagnostics.isEmpty)
        #expect(!key.statesKey)
        #expect(!key.statesClef)
    }

    @Test("A key with no clef says so; a key with one says that")
    func statesClef() {
        #expect(!parseKey("D").0.statesClef)
        #expect(parseKey("D").0.statesKey)
        #expect(parseKey("D clef=bass").0.statesClef)
        #expect(parseKey("D treble").0.statesClef)
    }

    @Test("A payload that is neither a key nor options is still reported, and changes nothing")
    func unreadableKey() {
        let (key, diagnostics) = parseKey("xyzzy")
        #expect(diagnostics.map(\.code) == [.malformedFieldPayload])
        #expect(!key.statesKey)
        #expect(!key.statesClef)
    }

    // MARK: In the tune header

    @Test("K:bass in the header is no key signature on a bass staff")
    func headerClefOnly() throws {
        let result = parse("K:bass\nCDEC|")
        #expect(result.diagnostics.isEmpty)
        let tune = try #require(result.score.tunes.first)
        #expect(tune.key.statesKey)
        #expect(tune.key.tonic == nil)
        #expect(tune.key.mode == .none)
        #expect(tune.voices.map(\.properties.clef) == [Self.bass])
    }

    // MARK: Part way through a voice

    @Test("K:bass part way through changes the clef where it is written, and not the key",
          arguments: ["K:bass", "K:clef=bass", "[K:clef=bass]"])
    func midTuneClefOnly(field: String) throws {
        let result = parse("K:D\nB4|\n\(field)\nD4|B,DFD|")
        #expect(result.diagnostics.isEmpty)
        let bars = measures(result)
        try #require(bars.count == 3)
        // No new signature to engrave: the key has not moved.
        #expect(bars.allSatisfy { $0.key == nil })
        #expect(clefChanges(bars[0]).isEmpty)
        #expect(clefChanges(bars[1]) == [Self.bass])
        // Written against the bar line, it comes before any of the bar's music.
        if case .clefChange = bars[1].events.first(where: {
            if case .spacer = $0 { return false } else { return true }
        }) {} else {
            Issue.record("the clef change is not the bar's first event")
        }
        #expect(clefChanges(bars[2]).isEmpty)
    }

    @Test("A clef change part way through a bar stands between the notes it falls between")
    func midBarClefChange() throws {
        let bars = measures(parse("K:D\nB2 [K:bass] D,2|"))
        try #require(bars.count == 1)
        let kinds = bars[0].events.compactMap { event -> String? in
            switch event {
            case .note:        return "note"
            case .clefChange:  return "clef"
            default:           return nil
            }
        }
        #expect(kinds == ["note", "clef", "note"])
    }

    @Test("A K: at the head of a voice is its opening clef, not a change")
    func openingClefIsNotAChange() throws {
        let result = parse("K:D\nK:bass\nD,4|")
        let bars = measures(result)
        try #require(bars.count == 1)
        #expect(clefChanges(bars[0]).isEmpty)
        #expect(result.score.tunes[0].voices[0].properties.clef == Self.bass)
    }

    @Test("A K: that restates the clef in force changes nothing")
    func restatedClefIsNotAChange() throws {
        let bars = measures(parse("K:D clef=bass\nD,4|\nK:bass\nD,4|"))
        try #require(bars.count == 2)
        #expect(bars.allSatisfy { clefChanges($0).isEmpty })
    }

    @Test("The kept key still sharpens: F after K:bass in D major is F♯, drawn plain")
    func keptKeyAlters() throws {
        let bars = measures(parse("K:D\nB4|\nK:bass\nF4|"))
        try #require(bars.count == 2)
        guard case .note(let note) = bars[1].events.first(where: {
            if case .note = $0 { return true } else { return false }
        }) else {
            Issue.record("no note in the second bar")
            return
        }
        #expect(note.pitch.alteration == Alteration(numerator: 1, denominator: 1))
        #expect(note.displayedAccidental == nil)
    }

    @Test("A key change with no clef keeps the clef in force")
    func midTuneKeyKeepsClef() throws {
        let bars = measures(parse("K:D\nB4|\nK:bass\nD4|\nK:G\nG,4|"))
        try #require(bars.count == 3)
        let key = try #require(bars[2].key)
        #expect(key.tonic?.step == .g)
        #expect(key.clef == Self.bass)
    }

    @Test("A key change with no clef keeps the voice's declared clef")
    func midTuneKeyKeepsDeclaredClef() throws {
        let bars = measures(parse("K:D\nV:1 clef=bass\nD4|\nK:G\nG,4|"))
        try #require(bars.count == 2)
        #expect(bars[1].key?.clef == Self.bass)
    }

    @Test("clef=treble is stated, so it puts the treble clef back")
    func statedTrebleRestores() throws {
        let bars = measures(parse("K:D clef=bass\nD4|\nK:clef=treble\nd4|\nK:G\nd4|"))
        try #require(bars.count == 3)
        #expect(clefChanges(bars[1]) == [Self.treble])
        // The key change after it is measured against the treble clef, not the bass.
        #expect(bars[2].key?.clef == Self.treble)
    }

    @Test("An unreadable K: part way through is reported and keeps key and clef")
    func midTuneUnreadable() throws {
        let result = parse("K:D clef=bass\nD4|\nK:xyzzy\nD4|")
        #expect(result.diagnostics.map(\.code) == [.malformedFieldPayload])
        let bars = measures(result)
        try #require(bars.count == 2)
        #expect(bars[1].key == nil)
        #expect(clefChanges(bars[1]).isEmpty)
    }
}
