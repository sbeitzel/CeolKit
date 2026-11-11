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
/// The note farthest from the middle line decides.  A group as far above it as below, like
/// a lone note on it, goes by the stems around it in its bar (#269): the way they all go,
/// else the way the ones in its beat or half-bar agree on, else down.
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
        try stems(inABC: "X:1\nT:Beams\nM:2/4\nL:1/8\n\(header)K:C\n\(body)\n")
    }

    /// As ``stemsByNote(_:header:)``, for a whole ABC file, whose noteheads are read left
    /// to right across every staff it draws — so give it one staff of music.
    private func stems(inABC abc: String) throws -> [(head: Head, stem: Stem, isUp: Bool)] {
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

    @Test("The note farthest from the middle line decides, and an even group follows its bar")
    func directionsByPitchAndBar() throws {
        let notes = try stemsByNote("GB Ac | ce Ac | ce Gd | GA Gd | GcBd | dGBc |")
        try #require(notes.count == 24)
        let expected: [Bool] = [true, true, true, true,       // GB up; Ac even, follows up
                                false, false, false, false,   // ce down; Ac follows down
                                false, false, false, false,   // ce down; Gd follows down
                                true, true, true, true,       // GA up; Gd follows up
                                false, false, false, false,   // GcBd even, nothing else: down
                                false, false, false, false]   // dGBc even, nothing else: down
        #expect(notes.map(\.isUp) == expected)
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: note.isUp))
        }
    }

    @Test("An even group takes nothing from the bar before it")
    func tieBreakStopsAtTheBarLine() throws {
        // The G stems up on its own; the Gd after the bar line has nothing in its own bar to
        // go by, and stems down.
        let notes = try stemsByNote("G2 z2 | Gd z2 |")
        try #require(notes.count == 3)
        #expect(notes.map(\.isUp) == [true, false, false])
    }

    // Issue #221, as #269 revised it: an unbeamed note on the middle line is the same
    // tie-break as an even group.

    @Test("A lone middle-line note follows the stems of its bar, wherever they stand in it")
    func middleLineNoteFollowsItsBar() throws {
        // In the last bar every B follows the G, the one stem decided by pitch — the first
        // B included, though it comes before the G and after the bar of down stems.
        let notes = try stemsByNote("G2 B2 G2 B2 | d2 B2 d2 B2 | B z G2 B z B2 |")
        try #require(notes.count == 12)
        let expected: [Bool] = [true, true, true, true,
                                false, false, false, false,
                                true, true, true, true]
        #expect(notes.map(\.isUp) == expected)
        for note in notes {
            #expect(try isAttached(note.stem, to: note.head, up: note.isUp))
        }
    }

    @Test("A lone middle-line note follows a beam group in its bar")
    func middleLineNoteFollowsABeamGroup() throws {
        #expect(try stemsByNote("ce B2 z2 |").map(\.isUp) == [false, false, false])
        #expect(try stemsByNote("GA B2 z2 |").map(\.isUp) == [true, true, true])
    }

    // Issue #269: where the stems of the bar go both ways, a middle-line note goes the way
    // of those in its beat, then its half-bar; where neither settles it, down.

    @Test("In a bar of mixed stems, a middle-line note follows its beat")
    func mixedBarFollowsTheBeat() throws {
        // 4/4: the B shares the first beat with the d (down), though the rest of the bar
        // stems up.
        let notes = try stemsByNote("d B G2 F2 E2 |", header: "M:4/4\n")
        try #require(notes.count == 5)
        #expect(notes.map(\.isUp) == [false, false, true, true, true])
    }

    @Test("In a bar of mixed stems, a middle-line note alone in its beat follows its half-bar")
    func mixedBarFollowsTheHalfBar() throws {
        // The B is alone in the third beat; the G in the same half-bar stems up.
        let up = try stemsByNote("d2 c2 B2 G2 |", header: "M:4/4\n")
        #expect(up.map(\.isUp) == [false, false, true, true])
        // The B is alone in the second beat; the d in the same half-bar stems down.
        let down = try stemsByNote("d2 B2 G2 F2 |", header: "M:4/4\n")
        #expect(down.map(\.isUp) == [false, false, true, true])
    }

    @Test("Where neither the beat nor the half-bar agrees, a middle-line note stems down")
    func mixedBarWithNoAgreementStemsDown() throws {
        // The first half-bar holds the d (down) and the G (up); most of the bar stems up,
        // but the B goes down.
        let notes = try stemsByNote("d G B2 E2 F2 |", header: "M:4/4\n")
        try #require(notes.count == 5)
        #expect(notes.map(\.isUp) == [false, true, false, true, true])
    }

    @Test("A compound meter's beat is a dotted note")
    func compoundMeterBeats() throws {
        // 6/8: the first beat is c d B (one dotted quarter, unbeamed here), the second G A F.
        // The bar is mixed, and the B follows the c and d it shares its beat with.
        let notes = try stemsByNote("c d B G A F |", header: "M:6/8\n")
        try #require(notes.count == 6)
        #expect(notes.map(\.isUp) == [false, false, false, true, true, true])
    }

    @Test("A bar of nothing but middle-line notes stems down")
    func onlyMiddleLineNotesStemDown() throws {
        let notes = try stemsByNote("G2 E2 | B2 B2 |")
        #expect(notes.map(\.isUp) == [true, true, false, false])
    }

    @Test("How a tune is stemmed does not depend on the tune before it")
    func noStemRunsOnIntoTheNextTune() throws {
        // The issue's file.  Tune One's last stem was once carried into tune Two, so its Bs
        // stemmed down after One and up on their own.  They stem down either way.
        let one = "X:1\nT:One\nL:1/4\nK:C\nc4 |]\n\n"
        let two = "X:2\nT:Two\nL:1/4\nK:C\nB4 B B B B |]\n"
        let alone = try stems(inABC: two)
        let after = try stems(inABC: one + two)
        #expect(alone.count == 4)
        #expect(alone.allSatisfy { !$0.isUp })
        #expect(after.count == 4)
        #expect(after.allSatisfy { !$0.isUp })
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
