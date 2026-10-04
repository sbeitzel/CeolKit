import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #222: every note was drawn where it would sit on a treble staff, whatever clef the
/// staff carried.  The clef glyph (#126, #127) and the key signature (#98) were already
/// placed for the clef, so a bass staff showed a correct F clef with treble noteheads under
/// it — `D` below the staff where abcm2ps draws it on a ledger line above.
///
/// Read out of the emitted document rather than the layout: what was wrong was the ink.
@Suite("Notes are placed for the clef in force")
struct ClefNotePositionTests {

    /// The staff position of every notehead drawn for `body` on a staff carrying `abcClef`,
    /// left to right: 0 = bottom line, 8 = top, one per diatonic step.
    private func positions(clef abcClef: String, body: String) throws -> [Int] {
        try positions(header: "K:C clef=\(abcClef)", body: body)
    }

    /// The same, under whatever header lines follow `L:`.
    private func positions(header: String, body: String) throws -> [Int] {
        let score = CeolKitParser().parse("""
            X:1
            T:Clef
            M:4/4
            L:1/4
            \(header)
            \(body) |
            """, options: .default).score
        let svgs   = try textProbeRenderer().render(score)
        let svg    = try #require(svgs.first)
        let page   = try #require(try SVGGeometry.pages(from: svgs).first)
        let system = try #require(page.systems.first)

        let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                     SMuFLGlyph.noteheadHalf.character,
                                     SMuFLGlyph.noteheadWhole.character]
        return svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
        ).compactMap { match -> (x: Double, y: Double)? in
            guard let x = Double(match.1), let y = Double(match.2),
                  let ch = String(match.3).first, heads.contains(ch) else { return nil }
            return (x, y)
        }
        .sorted { $0.x < $1.x }
        .map { Int(((system.bottomY - $0.y) / (system.staffLineGap / 2)).rounded()) }
    }

    // MARK: - The bug as filed

    /// The reproduction in #222, against what `abcm2ps -g` (8.14) draws for it: `D` just
    /// above the first ledger line over the bass staff, `B,` just above the top line, and `F`
    /// on the second ledger line.  Treble placement had put `D` below the staff.
    @Test("K:C bass draws D, B, and F above the staff, where abcm2ps draws them")
    func bassAsFiled() throws {
        #expect(try positions(clef: "bass", body: "D B, D F") == [11, 9, 11, 13])
    }

    // MARK: - Every clef

    /// The pitches on each clef's bottom, middle and top lines, in ABC.  Two staff positions
    /// per line, so they land on 0, 4 and 8.
    @Test("Each clef's bottom, middle and top lines name the pitches it says they do",
          arguments: [("treble",       "E B f"),
                      ("bass",         "G,, D, A,"),
                      ("bass3",        "B,, F, C"),
                      ("baritone",     "B,, F, C"),
                      ("alto",         "F, C G"),
                      ("tenor",        "D, A, E"),
                      ("soprano",      "C G d"),
                      ("mezzosoprano", "A, E B")])
    func linesOfEveryClef(abcClef: String, lines: String) throws {
        #expect(try positions(clef: abcClef, body: lines) == [0, 4, 8])
    }

    /// `clef=treble-8` sounds an octave below a treble staff but is written exactly where one
    /// is; the 8 under the clef is the whole of the difference on the page, and abcm2ps moves
    /// no note for it.
    @Test("An octave clef is written where its plain clef is",
          arguments: [("treble-8", "E B f"), ("treble+8", "E B f"), ("bass-8", "G,, D, A,")])
    func octaveClefMovesNothing(abcClef: String, lines: String) throws {
        #expect(try positions(clef: abcClef, body: lines) == [0, 4, 8])
    }

    /// A clef stated on `V:` rather than `K:` goes through the same staff, so the same rule.
    @Test("A clef on V: places its notes the same way")
    func voiceClef() throws {
        #expect(try positions(header: "K:C\nV:1 clef=alto", body: "F, C G C") == [0, 4, 8, 4])
    }

    // MARK: - Space for ledger lines

    /// The vertical layout counts ledger lines to reserve room above and below the staff, and
    /// counted them from treble too: middle C reserved a ledger line *below* a bass staff,
    /// where nothing is drawn, and none above it, where its ledger line is.
    @Test("Ledger space is reserved on the side of the staff the note is drawn on")
    func ledgerSpaceFollowsClef() throws {
        let config   = SVGRenderConfig()
        let metadata = try BravuraMetadata.load()
        let engine   = VerticalLayoutEngine(config: config, metadata: metadata)

        func extents(of pitch: Pitch, clef: Clef) -> (above: Double, below: Double) {
            let note = Note(pitch: pitch, writtenAccidental: nil, displayedAccidental: nil,
                            duration: Fraction(numerator: 1, denominator: 4), ties: .none,
                            slurs: .none, decorations: [], chordSymbol: nil, annotations: [],
                            beam: .single, lyrics: [],
                            source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0))
            let measure = Measure(
                openingBar: nil, events: [.note(note)],
                closingBar: BarLine(kind: .single,
                                    source: SourceRange(file: nil, byteOffset: 0, length: 0,
                                                        line: 0, column: 0)),
                endingNumber: nil,
                source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0),
                unitNoteLength: Fraction(numerator: 1, denominator: 8))
            let jm = JustifiedMeasure(
                source: SizedMeasure(measure: measure, naturalWidth: 100, eventOffsets: [0]),
                finalWidth: 100, eventOffsets: [0])
            let system = JustifiedSystem(measures: [jm], isLastSystem: true, sourceForced: false,
                                         clef: ClefSpec(clef: clef, octaveShift: 0))
            let s = engine.layout([system]).pages[0].systems[0]
            return (s.extraAbove, s.extraBelow)
        }

        let middleC = Pitch(step: .c, alteration: .natural, octave: 4)
        let onBass  = extents(of: middleC, clef: .bass)
        #expect(onBass.above >= config.staffSize)
        #expect(onBass.below == 0)

        // Two ledger lines below a bass staff, which a treble count put far lower still.
        let lowC = Pitch(step: .c, alteration: .natural, octave: 2)
        let low  = extents(of: lowC, clef: .bass)
        #expect(low.above == 0)
        #expect(abs(low.below - 2 * config.staffSize) < 1e-9)
    }
}
