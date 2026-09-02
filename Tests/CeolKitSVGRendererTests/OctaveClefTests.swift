//
//  OctaveClefTests.swift
//  CeolKitSVGRendererTests
//
//  ABC v2.2 §4.6: `clef=treble-8` and its relatives are drawn with the octave numeral the
//  reader needs to know the staff does not sound where it is written.
//

import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

/// SMuFL draws the numeral as part of the clef glyph, so the whole feature is a choice of
/// glyph — which is what these assert, together with the width that choice costs the header.
///
/// The codepoints behind the glyph names are checked against the specification's own table
/// by `SMuFLGlyphConformanceTests`; nothing here needs to repeat that.
@Suite("Octave clefs")
struct OctaveClefTests {

    private let metadata = try! BravuraMetadata.load()

    private func spec(_ clef: Clef, _ shift: Int) -> ClefSpec {
        ClefSpec(clef: clef, octaveShift: shift)
    }

    @Test("A G clef takes the numeral for every shift the standard allows")
    func gClefShifts() {
        #expect(clefGlyph(for: spec(.treble, 0)) == .gClef)
        #expect(clefGlyph(for: spec(.treble, -8)) == .gClef8vb)
        #expect(clefGlyph(for: spec(.treble, 8)) == .gClef8va)
        #expect(clefGlyph(for: spec(.treble, -15)) == .gClef15mb)
        #expect(clefGlyph(for: spec(.treble, 15)) == .gClef15ma)
    }

    @Test("So does an F clef, on both of the clefs drawn with one")
    func fClefShifts() {
        for clef in [Clef.bass, .baritone] {
            #expect(clefGlyph(for: spec(clef, 0)) == .fClef)
            #expect(clefGlyph(for: spec(clef, -8)) == .fClef8vb)
            #expect(clefGlyph(for: spec(clef, 8)) == .fClef8va)
            #expect(clefGlyph(for: spec(clef, -15)) == .fClef15mb)
            #expect(clefGlyph(for: spec(clef, 15)) == .fClef15ma)
        }
    }

    @Test("A C clef has only the octave-down form, and falls back to the plain glyph")
    func cClefShifts() {
        // SMuFL defines `cClef8vb` and no other shifted C clef.  Where there is no glyph the
        // plain one is drawn: the transposition is a property of the voice and has already
        // been applied to the notes — only the reader's reminder of it is missing.
        for clef in [Clef.alto, .tenor, .soprano, .mezzoSoprano] {
            #expect(clefGlyph(for: spec(clef, 0)) == .cClef)
            #expect(clefGlyph(for: spec(clef, -8)) == .cClef8vb)
            #expect(clefGlyph(for: spec(clef, 8)) == .cClef)
            #expect(clefGlyph(for: spec(clef, -15)) == .cClef)
        }
    }

    @Test("clef=none draws nothing, shifted or not")
    func noClef() {
        #expect(clefGlyph(for: spec(.none, 0)) == nil)
        #expect(clefGlyph(for: spec(.none, -8)) == nil)
    }

    @Test("Percussion has no octave form to take")
    func percussion() {
        #expect(clefGlyph(for: spec(.percussion, 0)) == .unpitchedPercussionClef1)
        #expect(clefGlyph(for: spec(.percussion, -8)) == .unpitchedPercussionClef1)
    }

    @Test("The header reserves the width of the glyph it will actually draw")
    func headerWidthFollowsTheGlyph() {
        // `gClef8vb` is no wider than `gClef` in Bravura but `fClef8vb` is not the same
        // width as `fClef`, and either way the reservation has to be the *drawn* glyph's:
        // the key signature after it starts where the space was kept.
        for (clef, shift) in [(Clef.treble, -8), (.bass, -8), (.bass, 8), (.alto, -8)] {
            let glyph = clefGlyph(for: spec(clef, shift))
            let expected = (metadata.glyphBBoxes[glyph!.rawValue]!.width + 0.5) * 8
            #expect(clefHeaderWidth(for: spec(clef, shift), metadata: metadata, staffSize: 8)
                    == expected)
        }
    }
}
