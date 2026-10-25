//
//  TupletRenderingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #231: a tuplet's notes are drawn — spaced, stemmed and beamed like any others, at
//  the length they were written — with its number over them, and a bracket where the notes
//  are not exactly one beam group.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("Tuplets are drawn (#231)")
struct TupletRenderingTests {

    private let metadata = try! BravuraMetadata.load()

    private func tune(_ body: String, meter: String = "4/4") -> String {
        "X:1\nT:Tuplets\nM:\(meter)\nL:1/8\nK:C\n\(body)\n"
    }

    /// The tune's first page, in `fontFace` mode so every glyph is a `<text>` run.
    private func svg(_ abc: String) throws -> String {
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let score = CeolKitParser().parse(abc, options: .default).score
        return try #require(try SVGRenderer(config: config).render(score).first)
    }

    private func count(_ glyph: SMuFLGlyph, in svg: String) -> Int {
        svg.filter { $0 == glyph.character }.count
    }

    private struct Line {
        let x1, y1, x2, y2, width: Double
    }

    private func lines(in svg: String) -> [Line] {
        svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"[^>]*stroke-width="([0-9.]+)"/)
            .compactMap { m in
                guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                      let y2 = Double(m.4), let w = Double(m.5) else { return nil }
                return Line(x1: x1, y1: y1, x2: x2, y2: y2, width: w)
            }
    }

    /// How many lines are `spaces` staff spaces thick, bar lines aside — a thin bar is as
    /// thick as a tuplet bracket, and a thick one as a beam.  The first line is a staff
    /// line, which gives the staff space: Bravura makes it `staffLineThickness` thick.
    private func lines(ofThickness spaces: Double, in svg: String) throws -> Int {
        let all = lines(in: svg)
        let space = try #require(all.first).width / metadata.engravingDefaults.staffLineThickness
        return all.filter { line in
            let isBar = line.x1 == line.x2 && abs(abs(line.y2 - line.y1) - 4 * space) < 0.01
            return !isBar && abs(line.width - spaces * space) < 0.01
        }.count
    }

    @Test("A triplet's notes are drawn, with or without a space after the (3",
          arguments: ["(3efg a2 z4 |]", "(3 efg a2 z4 |]"])
    func notesAreDrawn(_ body: String) throws {
        let page = try svg(tune(body))
        #expect(count(.noteheadBlack, in: page) == 4)
    }

    @Test("A triplet of eighths is beamed as eighths, with one beam")
    func eighthsHaveOneBeam() throws {
        let page = try svg(tune("(3efg z2 z4 |]"))
        #expect(try lines(ofThickness: metadata.engravingDefaults.beamThickness, in: page) == 1)
    }

    @Test("The number over a tuplet is p", arguments: [
        ("(3efg z2 z4 |]", [SMuFLGlyph.tuplet3]),
        ("(5efgab z3 z2 |]", [.tuplet5]),
        ("(3:2:2e2f z2 z4 |]", [.tuplet3]),
    ])
    func numberIsP(_ body: String, _ digits: [SMuFLGlyph]) throws {
        let page = try svg(tune(body))
        for digit in digits { #expect(count(digit, in: page) == 1) }
    }

    @Test("A tuplet that is one beam group has no bracket")
    func beamedTripletHasNoBracket() throws {
        let page = try svg(tune("(3efg z2 z4 |]"))
        #expect(try lines(ofThickness: metadata.engravingDefaults.tupletBracketThickness,
                          in: page) == 0)
    }

    @Test("A tuplet that is not one beam group is bracketed", arguments: [
        "(3e2f2g2 z2 |]",      // unbeamed quarters
        "(3zfg z2 z4 |]",      // a rest in it
        "c(3efg z z4 |]",      // beamed with a note outside it
    ])
    func unbeamedTripletIsBracketed(_ body: String) throws {
        let page = try svg(tune(body))
        // Two hooks and the rule either side of the number.
        #expect(try lines(ofThickness: metadata.engravingDefaults.tupletBracketThickness,
                          in: page) == 4)
    }

    // MARK: - Layout

    private func firstMeasure(_ abc: String) throws -> Measure {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try #require(score.tunes.first?.voices.first?.staves.first?.measures.first)
    }

    @Test("The sizer opens a tuplet out into the bar, a column per note")
    func sizerOpensTupletOut() throws {
        let sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
        let sized = sizer.size(try firstMeasure(tune("(3efg a2 z4 |]")))
        #expect(sized.measure.events.count == sized.eventOffsets.count)
        #expect(sized.tuplets == [TupletSpan(eventIndices: [0, 1, 2], p: 3, q: 2)])
        let offsets = sized.eventOffsets
        #expect(offsets[0] < offsets[1] && offsets[1] < offsets[2] && offsets[2] < offsets[3])
    }

    @Test("A tuplet lasts as long as the notes it stands in for, counted once")
    func tupletLengthIsNotScaledTwice() throws {
        let measure = try firstMeasure(tune("(3efg a2 z4 |]"))
        guard case .tuplet(let tuplet) = measure.events.first else {
            Issue.record("Expected the bar to open with a tuplet")
            return
        }
        let metrics = ColumnMetrics(config: SVGRenderConfig(), metadata: metadata)
        // Three eighths in the time of two: two units of L:1/8.
        #expect(metrics.tupletDuration(tuplet) == 2)
        #expect(Rational.quarters(of: .tuplet(tuplet), unitNoteLength: measure.unitNoteLength)
                == Rational(1, 1))
    }

    @Test("A tuplet's notes are drawn at the length they were written")
    func writtenLengthIsRestored() {
        let note = Note(pitch: Pitch(step: .e, alteration: .natural, octave: 5),
                        writtenAccidental: nil, displayedAccidental: nil,
                        duration: Fraction(numerator: 2, denominator: 3),
                        ties: .none, slurs: .none, decorations: [], chordSymbol: nil,
                        annotations: [], beam: .start, lyric: nil,
                        source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 0,
                                            column: 0))
        let span = TupletSpan(eventIndices: [0], p: 3, q: 2)
        guard case .note(let written) = TupletExpansion.written(.note(note), in: span) else {
            Issue.record("Expected a note")
            return
        }
        #expect(written.duration == Fraction(numerator: 1, denominator: 1))
    }
}
