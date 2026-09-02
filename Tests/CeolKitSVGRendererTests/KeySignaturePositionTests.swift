import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #98: a key signature names pitches, so where its accidentals sit depends on the
/// clef the staff carries. `keyAccidentals` used one treble-clef table for every clef, and
/// two entries of that table were themselves an octave out.
@Suite("Key signature positions per clef")
struct KeySignaturePositionTests {

    // MARK: - Reading positions back off the page

    /// The staff positions of every `glyph` drawn on the staff of `system`, left to right.
    ///
    /// 0 = bottom line, 8 = top line — the same scale `KeyAccidental` uses. Only glyphs
    /// within a staff's height of it are counted, which on a two-staff system is enough to
    /// keep each staff's signature to itself.
    private func positions(of glyph: SMuFLGlyph, on system: SystemGeometry,
                           in svg: String) -> [Int] {
        let character = String(glyph.character)
        var found: [(x: Double, position: Int)] = []
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard segment.contains(character) else { continue }
            func attribute(_ name: String) -> Double? {
                guard let start = segment.range(of: "\(name)=\"") else { return nil }
                let after = segment[start.upperBound...]
                guard let end = after.firstIndex(of: "\"") else { return nil }
                return Double(after[after.startIndex..<end])
            }
            guard let x = attribute("x"), let y = attribute("y") else { continue }
            let position = (system.bottomY - y) / (system.staffLineGap / 2)
            guard position > -6, position < 14 else { continue }
            found.append((x, Int(position.rounded())))
        }
        return found.sorted { $0.x < $1.x }.map(\.position)
    }

    private func render(_ abc: String) throws -> (svg: String, page: PageGeometry) {
        let score = CeolKitParser().parse(abc, options: .default).score
        let svgs = try textProbeRenderer().render(score)
        let svg = try #require(svgs.first)
        let page = try #require(try SVGGeometry.pages(from: svgs).first)
        return (svg, page)
    }

    /// A two-staff tune: voice 1 on the default treble clef, voice 2 on `clef`.
    private func twoStaves(key: String, secondClef: String) throws -> (svg: String, page: PageGeometry) {
        try render("""
            X:1
            T:Clefs
            M:4/4
            L:1/4
            K:\(key)
            V:1
            V:2 clef=\(secondClef)
            V:1
            cdec |
            V:2
            CDEC |
            """)
    }

    // MARK: - The bug as filed

    @Test("A bass staff draws its key signature at bass-clef positions")
    func bassClefKeySignature() throws {
        let (svg, page) = try twoStaves(key: "E", secondClef: "bass")
        #expect(page.systems.count == 2)
        // Read as pitches both staves say F♯ C♯ G♯ D♯; before the fix the bass staff took
        // the treble offsets and said A♯ E♯ B♯ F♯.
        #expect(positions(of: .accidentalSharp, on: page.systems[0], in: svg) == [8, 5, 9, 6])
        #expect(positions(of: .accidentalSharp, on: page.systems[1], in: svg) == [6, 3, 7, 4])
    }

    @Test("Three sharps put G♯ in the space above a treble staff")
    func trebleThirdSharpIsAboveTheStaff() throws {
        let (svg, page) = try render("""
            X:1
            T:A major
            M:4/4
            L:1/4
            K:A
            cdec |
            """)
        let staff = try #require(page.systems.first)
        #expect(positions(of: .accidentalSharp, on: staff, in: svg) == [8, 5, 9])
    }

    @Test("K:Cb puts F♭ in the first space")
    func cFlatMajorSeventhFlat() throws {
        let (svg, page) = try render("""
            X:1
            T:C flat major
            M:4/4
            L:1/4
            K:Cb
            cdec |
            """)
        let staff = try #require(page.systems.first)
        #expect(positions(of: .accidentalFlat, on: staff, in: svg) == [4, 7, 3, 6, 2, 5, 1])
    }

    @Test("One and two accidentals on a treble staff are where they always were")
    func fewAccidentalsAreUnchanged() throws {
        for (key, glyph, expected) in [("G", SMuFLGlyph.accidentalSharp, [8]),
                                       ("D", .accidentalSharp, [8, 5]),
                                       ("F", .accidentalFlat, [4]),
                                       ("Bb", .accidentalFlat, [4, 7])] {
            let (svg, page) = try render("""
                X:1
                T:\(key)
                M:4/4
                L:1/4
                K:\(key)
                cdec |
                """)
            let staff = try #require(page.systems.first)
            #expect(positions(of: glyph, on: staff, in: svg) == expected, "K:\(key)")
        }
    }

    @Test("A percussion staff draws no key signature")
    func percussionDrawsNothing() throws {
        let (svg, page) = try twoStaves(key: "E", secondClef: "perc")
        #expect(page.systems.count == 2)
        #expect(positions(of: .accidentalSharp, on: page.systems[1], in: svg).isEmpty)
        // The treble voice above it still gets its four, so the tune really is in E.
        #expect(positions(of: .accidentalSharp, on: page.systems[0], in: svg).count == 4)
    }

    @Test("K:none draws no key signature")
    func keyNoneDrawsNothing() throws {
        let (svg, page) = try render("""
            X:1
            T:No key
            M:4/4
            L:1/4
            K:none
            cdec |
            """)
        let staff = try #require(page.systems.first)
        #expect(positions(of: .accidentalSharp, on: staff, in: svg).isEmpty)
        #expect(positions(of: .accidentalFlat, on: staff, in: svg).isEmpty)
    }

    // MARK: - The whole table, clef by clef

    /// The key signature of `key`, laid out on `clef`, as staff positions.
    private func table(_ key: String, _ clef: Clef) throws -> [Int] {
        let score = CeolKitParser().parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            K:\(key)
            cdec |
            """, options: .default).score
        let signature = try #require(score.tunes.first?.key)
        return keyAccidentals(for: signature, clef: ClefSpec(clef: clef, octaveShift: 0))
            .map(\.staffPosition)
    }

    /// Every accidental of a seven-accidental signature is on the staff, or — for the bass
    /// F♭ alone — the position immediately below it, where a key signature draws no ledger
    /// line. The C clefs earn their own tables precisely because a plain shift would push
    /// accidentals off the staff.
    @Test("Seven sharps and seven flats stay on the staff on every pitched clef",
          arguments: [Clef.treble, .bass, .baritone, .alto, .tenor, .soprano, .mezzoSoprano])
    func sevenAccidentalsFitTheStaff(clef: Clef) throws {
        let sharps = try table("C#", clef)
        let flats  = try table("Cb", clef)
        #expect(sharps.count == 7)
        #expect(flats.count == 7)
        // The treble G♯ sits one position above the top line by convention; nothing else
        // leaves the staff except the bass F♭, one below the bottom line.
        #expect(sharps.allSatisfy { $0 >= 0 && $0 <= 9 })
        #expect(flats.allSatisfy { $0 >= -1 && $0 <= 8 })
    }

    /// The engraved positions, clef by clef, in circle-of-fifths order.
    @Test("The accidental tables are the conventional engraving",
          arguments: [(Clef.treble,       [8, 5, 9, 6, 3, 7, 4], [4, 7, 3, 6, 2, 5, 1]),
                      (.bass,             [6, 3, 7, 4, 1, 5, 2], [2, 5, 1, 4, 0, 3, -1]),
                      (.baritone,         [4, 8, 5, 2, 6, 3, 7], [7, 3, 6, 2, 5, 1, 4]),
                      (.alto,             [7, 4, 8, 5, 2, 6, 3], [3, 6, 2, 5, 1, 4, 0]),
                      (.tenor,            [2, 6, 3, 7, 4, 8, 5], [5, 8, 4, 7, 3, 6, 2]),
                      (.soprano,          [3, 7, 4, 8, 5, 2, 6], [6, 2, 5, 1, 4, 0, 3]),
                      (.mezzoSoprano,     [5, 2, 6, 3, 7, 4, 8], [8, 4, 7, 3, 6, 2, 5])])
    func tablesMatchTheEngravedConvention(clef: Clef, sharps: [Int], flats: [Int]) throws {
        #expect(try table("C#", clef) == sharps)
        #expect(try table("Cb", clef) == flats)
    }

    /// Consecutive accidentals of a signature move by a fifth or a fourth, in whichever
    /// octave keeps them on the staff — the property that makes each table a signature
    /// rather than seven unrelated positions.
    @Test("Consecutive accidentals are a fifth or a fourth apart",
          arguments: [Clef.treble, .bass, .baritone, .alto, .tenor, .soprano, .mezzoSoprano])
    func accidentalsStepByFifthsAndFourths(clef: Clef) throws {
        for key in ["C#", "Cb"] {
            let table = try table(key, clef)
            for (a, b) in zip(table, table.dropFirst()) {
                #expect(abs(b - a) == 3 || abs(b - a) == 4,
                        "\(clef) \(key): \(a) → \(b) is neither a fourth nor a fifth")
            }
        }
    }

    @Test("An octave-shifted clef does not move the key signature",
          arguments: [-8, 8])
    func octaveShiftDoesNotMoveTheSignature(shift: Int) throws {
        let score = CeolKitParser().parse("""
            X:1
            T:T
            M:4/4
            L:1/4
            K:E
            cdec |
            """, options: .default).score
        let signature = try #require(score.tunes.first?.key)
        let plain   = keyAccidentals(for: signature, clef: ClefSpec(clef: .treble, octaveShift: 0))
        let shifted = keyAccidentals(for: signature, clef: ClefSpec(clef: .treble, octaveShift: shift))
        #expect(plain.map(\.staffPosition) == shifted.map(\.staffPosition))
    }
}
