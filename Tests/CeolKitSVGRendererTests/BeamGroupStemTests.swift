import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #218: a beam group has one stem direction, and every stem in it is placed for that
/// direction — on the notehead's right for up, its left for down.
///
/// Each stem used to be placed for the direction its own note would have taken alone, and
/// then drawn the way the group's *first* note went.  In `Gd` the `d` was placed stem-down,
/// at its notehead's left edge, and drawn up to the beam.
///
/// The expected directions are abcm2ps's (8.14, `-g`): the note farthest from the middle
/// line decides, and a group as far above it as below follows the stem before it.
@Suite("Beam group stem direction (#218)")
struct BeamGroupStemTests {

    private struct Stem { let x, top, bottom: Double }
    private struct Head { let x, y: Double }

    private let metadata: BravuraMetadata
    private let s = SVGRenderConfig().scaledStaffSize
    /// SVG coordinates are written to three decimals.
    private let tolerance = 0.002

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    private var stemThickness: Double { metadata.engravingDefaults.stemThickness * s }

    /// Every note of `body` with the stem drawn from it, left to right, and which way that
    /// stem goes.  Written for music where every note has exactly one stem, so the n-th
    /// notehead and the n-th stem from the left belong together.
    private func stemsByNote(_ body: String, header: String = "") throws
        -> [(head: Head, stem: Stem, isUp: Bool)] {
        let abc = "X:1\nT:Beams\nM:2/4\nL:1/8\n\(header)K:C\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        let svg = try textProbeRenderer().render(score).joined()

        let heads = svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/)
            .compactMap { m -> Head? in
                guard let x = Double(m.1), let y = Double(m.2),
                      String(m.3).first == SMuFLGlyph.noteheadBlack.character else { return nil }
                return Head(x: x, y: y)
            }
            .sorted { $0.x < $1.x }
        let stems = svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
        ).compactMap { m -> Stem? in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), let w = Double(m.5),
                  x1 == x2, y1 != y2, abs(w - stemThickness) < 0.01 else { return nil }
            return Stem(x: x1, top: min(y1, y2), bottom: max(y1, y2))
        }
        .sorted { $0.x < $1.x }

        try #require(heads.count == stems.count)
        return zip(heads, stems).map { head, stem in
            // An up stem runs from just above the notehead's centre to well above it.
            (head, stem, stem.bottom < head.y + s / 2 && stem.top < head.y - s)
        }
    }

    /// Whether `stem` is where `head`'s SMuFL anchor for that direction puts it.
    private func isAttached(_ stem: Stem, to head: Head, up: Bool) throws -> Bool {
        let anchor = try #require(metadata.anchor(up ? "stemUpSE" : "stemDownNW",
                                                  on: .noteheadBlack))
        let edge = up ? stem.x + stemThickness / 2 : stem.x - stemThickness / 2
        return abs(edge - (head.x + anchor.x * s)) < tolerance
    }

    @Test("Every stem of a group straddling the middle line is on the side its direction needs")
    func stemsSitOnTheirDirectionsSide() throws {
        // G below the middle line, d above it, f above that: the group stems down, and the
        // G — which alone would stem up — has to be placed as a down stem too.
        let notes = try stemsByNote("Gdf z |")
        try #require(notes.count == 3)
        #expect(notes.allSatisfy { !$0.isUp })
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: false))
        }
    }

    @Test("The note farthest from the middle line decides, and a tie follows the stem before")
    func directionsMatchAbcm2ps() throws {
        let notes = try stemsByNote("GB Ac | ce Ac | ce Gd | GA Gd | GcBd | dGBc |")
        try #require(notes.count == 24)
        let expected: [Bool] = [true, true, true, true,       // GB up; Ac even, follows up
                                false, false, false, false,   // ce down; Ac follows down
                                false, false, false, false,   // ce down; Gd follows down
                                true, true, true, true,       // GA up; Gd follows up
                                true, true, true, true,       // GcBd even, follows up
                                true, true, true, true]       // dGBc even, follows up
        #expect(notes.map(\.isUp) == expected)
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: note.isUp))
        }
    }

    @Test("An even group follows an unbeamed stem in the bar before")
    func tieBreakRunsAcrossTheBarLine() throws {
        // The quarter e stems down on its own; the Gd after the bar line follows it.
        let notes = try stemsByNote("e2 z2 | Gd z2 |")
        try #require(notes.count == 3)
        #expect(notes.map(\.isUp) == [false, false, false])
    }

    // Issue #221: an unbeamed note on the middle line is the same tie-break as an even
    // group — it follows the stem before it in the part, and stems up where there is none.

    @Test("A lone middle-line note follows the stem before it, across bar lines and rests")
    func middleLineNoteFollowsThePreviousStem() throws {
        // The issue's tune at L:1/8.  abcm2ps 8.14 (-g): B up in the first bar, down in the
        // second; the last bar's first B follows the second bar's last, past the rest after
        // it, and the G turns everything after it back up.
        let notes = try stemsByNote("G2 B2 G2 B2 | d2 B2 d2 B2 | B z G2 B z B2 |")
        try #require(notes.count == 12)
        let expected: [Bool] = [true, true, true, true,
                                false, false, false, false,
                                false, true, true, true]
        #expect(notes.map(\.isUp) == expected)
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: note.isUp))
        }
    }

    @Test("A lone middle-line note follows a beam group before it")
    func middleLineNoteFollowsABeamGroup() throws {
        let notes = try stemsByNote("ce B2 z2 |")
        try #require(notes.count == 3)
        #expect(notes.map(\.isUp) == [false, false, false])
    }

    @Test("A voice's own stem= still decides a middle-line note")
    func voiceDirectionWinsOnTheMiddleLine() throws {
        let notes = try stemsByNote("[V:1] d2 B2 |", header: "V:1 stem=up\n")
        try #require(notes.count == 2)
        #expect(notes.allSatisfy { $0.isUp })
    }

    @Test("A voice's own stem= still decides every stem of its groups")
    func voiceDirectionWins() throws {
        // GB would stem up by pitch.
        let notes = try stemsByNote("[V:1] GB z2 |", header: "V:1 stem=down\n")
        try #require(notes.count == 2)
        #expect(notes.allSatisfy { !$0.isUp })
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: false))
        }
    }
}
