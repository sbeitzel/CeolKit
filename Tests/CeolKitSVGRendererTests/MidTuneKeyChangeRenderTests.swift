import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #129: a `K:` in the tune body must be engraved where it happens — the naturals
/// that cancel the outgoing signature, then the incoming one's own accidentals, drawn at
/// the head of the measure the change lands on.
///
/// The renderer used to draw only the signature at a staff head, so a tune that changed key
/// part way through showed no accidental anywhere but there.
@Suite("Mid-tune key change rendering")
struct MidTuneKeyChangeRenderTests {

    /// Every SMuFL glyph the page draws, in document order, as `(character, x, y)`.
    ///
    /// `<text>` is the probe for the same reason the mid-line meter suite uses it: it
    /// carries the position of each run as attributes rather than in a transform.
    private func glyphs(_ svg: String) -> [(char: Character, x: Double, y: Double)] {
        var found: [(Character, Double, Double)] = []
        for segment in svg.components(separatedBy: "<text ").dropFirst() {
            guard let close = segment.range(of: ">"),
                  let end = segment.range(of: "</text>") else { continue }
            let attrs = segment[segment.startIndex..<close.lowerBound]
            let body  = segment[close.upperBound..<end.lowerBound]
            guard let char = body.first, char.unicodeScalars.first!.value > 0xE000 else { continue }
            guard let x = attribute("x", in: attrs), let y = attribute("y", in: attrs) else { continue }
            found.append((char, x, y))
        }
        return found
    }

    private func attribute(_ name: String, in attrs: Substring) -> Double? {
        guard let start = attrs.range(of: "\(name)=\"") else { return nil }
        let rest = attrs[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return Double(rest[rest.startIndex..<end])
    }

    private func page(_ abc: String) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        let pages = try textProbeRenderer().render(score)
        return try #require(pages.first)
    }

    private func count(_ glyph: SMuFLGlyph, in svg: String) -> Int {
        glyphs(svg).filter { $0.char == glyph.character }.count
    }

    // MARK: The two forms the issue reported

    @Test("A K: on its own line draws the new signature")
    func keyFieldOnItsOwnLineIsDrawn() throws {
        let svg = try page("""
            X:1
            T:Key change on its own line
            M:4/4
            L:1/4
            K:C
            CDEF|
            K:G
            GABC|
            """)

        #expect(count(.accidentalSharp, in: svg) == 1,
                "the one sharp of K:G must be drawn where the key changes")
    }

    @Test("An inline [K:] draws the new signature")
    func inlineKeyFieldIsDrawn() throws {
        let svg = try page("""
            X:1
            T:Key change inline
            M:4/4
            L:1/4
            K:C
            CDEF|[K:G]GABC|
            """)

        #expect(count(.accidentalSharp, in: svg) == 1)
    }

    @Test("A K: reached through a line continuation draws its change mid-system")
    func continuationKeyChangeIsDrawn() throws {
        // The third acceptance bullet of #107, which was blocked on there being anything in
        // the model for the renderer to draw: the `\` keeps both bars on one system, and the
        // key changes inside it.
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:C
            CDEF|\\
            K:G
            GABC|
            """)
        let drawn = glyphs(svg)

        #expect(drawn.filter { $0.char == SMuFLGlyph.gClef.character }.count == 1,
                "the continuation keeps the music on one system")
        let sharpX = try #require(drawn.first { $0.char == SMuFLGlyph.accidentalSharp.character }?.x)
        let noteXs = drawn.filter { $0.char == SMuFLGlyph.noteheadBlack.character }.map(\.x)
        try #require(noteXs.count == 8)
        #expect(noteXs[3] < sharpX && sharpX < noteXs[4])
    }

    // MARK: Where it lands

    @Test("The new signature sits in the body of the music, after the notes before it")
    func signatureSitsAtThePointOfChange() throws {
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:C
            CDEF|[K:G]GABC|
            """)
        let drawn = glyphs(svg)

        let sharpX = try #require(drawn.first { $0.char == SMuFLGlyph.accidentalSharp.character }?.x)
        let noteXs = drawn.filter { $0.char == SMuFLGlyph.noteheadBlack.character }.map(\.x)
        try #require(noteXs.count == 8)

        #expect(noteXs[3] < sharpX, "the sharp follows the last note of the C major bar")
        #expect(sharpX < noteXs[4], "and precedes the first note of the G major bar")
    }

    @Test("Nothing is drawn in the body when the key never moves")
    func noChangeDrawsNothingExtra() throws {
        // The control for the two tests above: the same music in one key throughout draws
        // its signature once, at the staff head.
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:G
            CDEF|GABC|
            """)
        let drawn = glyphs(svg)
        let sharps = drawn.filter { $0.char == SMuFLGlyph.accidentalSharp.character }
        let clefX = try #require(drawn.first { $0.char == SMuFLGlyph.gClef.character }?.x)
        let firstNoteX = try #require(drawn.first { $0.char == SMuFLGlyph.noteheadBlack.character }?.x)

        try #require(sharps.count == 1)
        #expect(sharps[0].x > clefX && sharps[0].x < firstNoteX, "drawn at the staff head")
    }

    // MARK: Cancelling the outgoing signature

    @Test("Accidentals the new key drops are cancelled with naturals")
    func outgoingAccidentalsAreCancelled() throws {
        // D major (F♯ C♯) to E♭ major (B♭ E♭ A♭): both sharps go, so both are cancelled,
        // and the three flats follow them.
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:D
            DEFG|[K:Eb]EFGA|
            """)

        #expect(count(.accidentalNatural, in: svg) == 2)
        #expect(count(.accidentalFlat, in: svg) == 3)
        #expect(count(.accidentalSharp, in: svg) == 2, "only the two at the staff head")
    }

    @Test("A key with no accidentals is drawn as naturals alone")
    func returnToCMajorIsAllNaturals() throws {
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:Eb
            EFGA|[K:C]CDEF|
            """)

        #expect(count(.accidentalNatural, in: svg) == 3,
                "all three flats of E♭ major are cancelled")
        #expect(count(.accidentalFlat, in: svg) == 3, "only the three at the staff head")
    }

    @Test("An accidental the new key keeps is not cancelled")
    func retainedAccidentalsTakeNoNatural() throws {
        // D major (F♯ C♯) to G major (F♯): only C♯ goes, and F♯ is simply restated.
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:D
            DEFG|[K:G]GABc|
            """)

        #expect(count(.accidentalNatural, in: svg) == 1, "C♯ alone is cancelled")
        #expect(count(.accidentalSharp, in: svg) == 3, "two at the head, one at the change")
    }

    @Test("The naturals come before the new signature")
    func naturalsPrecedeTheNewSignature() throws {
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:D
            DEFG|[K:Eb]EFGA|
            """)
        let drawn = glyphs(svg)

        let lastNaturalX = try #require(
            drawn.filter { $0.char == SMuFLGlyph.accidentalNatural.character }.map(\.x).max())
        let firstFlatX = try #require(
            drawn.filter { $0.char == SMuFLGlyph.accidentalFlat.character }.map(\.x).min())

        #expect(lastNaturalX < firstFlatX)
    }

    // MARK: The space it is given

    @Test("The bar the key changes in is wider than the same bar without the change")
    func theChangeIsGivenRoom() throws {
        // Natural width, not justified: the sizer has to reserve the signature's glyphs
        // before the first note, or they would be drawn over it.
        func naturalWidths(_ abc: String) -> [Double] {
            let score = CeolKitParser().parse(abc, options: .default).score
            let config = SVGRenderConfig()
            let metadata = try! BravuraMetadata.load()
            let sizer = MeasureSizer(config: config, metadata: metadata)
            let measures = score.tunes[0].voices[0].staves.flatMap(\.measures)
            let clef = score.tunes[0].voices[0].properties.clef
            var key: KeySignature? = score.tunes[0].key
            return measures.map { measure in
                var change: KeyChange? = nil
                if let newKey = measure.key {
                    change = KeyChange(from: key, to: newKey, clef: clef)
                    key = newKey
                }
                return sizer.size(measure, keyChange: change).naturalWidth
            }
        }

        let changed = naturalWidths("""
            X:1
            M:4/4
            L:1/4
            K:C
            CDEF|[K:Eb]EFGA|
            """)
        let unchanged = naturalWidths("""
            X:1
            M:4/4
            L:1/4
            K:C
            CDEF|EFGA|
            """)
        try #require(changed.count == 2 && unchanged.count == 2)

        #expect(changed[0] == unchanged[0], "the bar before the change is untouched")
        #expect(changed[1] > unchanged[1], "the bar it lands on makes room for three flats")
    }

    // MARK: Clefs

    @Test("The signature follows the clef the staff carries")
    func signatureFollowsTheClef() throws {
        // #98 established this for the opening signature; a change is placed the same way,
        // because it reads the same table.  F♯ sits on the top line in treble (staff
        // position 8) and on the fourth line in bass (position 6).
        let c = KeySignature(tonic: PitchClass(step: .c, alteration: .natural), mode: .major,
                             modifications: [], explicit: false,
                             clef: ClefSpec(clef: .treble, octaveShift: 0),
                             transposition: .none, staffProperties: StaffProperties(staffLines: 5),
                             source: .emptySourceRange)
        let g = KeySignature(tonic: PitchClass(step: .g, alteration: .natural), mode: .major,
                             modifications: [], explicit: false,
                             clef: ClefSpec(clef: .treble, octaveShift: 0),
                             transposition: .none, staffProperties: StaffProperties(staffLines: 5),
                             source: .emptySourceRange)

        func positions(_ clef: Clef) -> [Int] {
            keyChangeAccidentals(for: KeyChange(from: c, to: g,
                                                clef: ClefSpec(clef: clef, octaveShift: 0)))
                .map(\.staffPosition)
        }

        #expect(positions(.treble) == [8])
        #expect(positions(.bass) == [6])
        #expect(keyChangeAccidentals(for: KeyChange(from: c, to: g,
                                                    clef: ClefSpec(clef: .percussion,
                                                                   octaveShift: 0))).isEmpty)
    }

    @Test("A bass staff draws its mid-tune change too")
    func bassStaffDrawsTheChange() throws {
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:C clef=bass
            CDEF|[K:G]GABC|
            """)

        #expect(count(.accidentalSharp, in: svg) == 1)
    }

    @Test("A percussion staff draws no signature at all")
    func percussionStaffDrawsNothing() throws {
        let svg = try page("""
            X:1
            M:4/4
            L:1/4
            K:C clef=perc
            CDEF|[K:G]GABC|
            """)

        #expect(count(.accidentalSharp, in: svg) == 0)
        #expect(count(.accidentalNatural, in: svg) == 0)
    }
}
