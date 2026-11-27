//
//  CentredRestTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #300: a rest that fills its whole measure is centred between the measure's bar
//  lines, as abcm2ps 8.14 draws it (`draw_rest`, "if rest alone in the measure … center"),
//  rather than standing at the left where a first note would.
//

import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

@Suite("Whole-measure rests are centred")
struct CentredRestTests {

    private let staffSize = SVGRenderConfig().scaledStaffSize

    private func layout(_ abc: String) throws -> ResolvedLayout {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score).layout
    }

    /// One justified line of `body`, in `M:4/4` unless the body changes it.
    private func tune(_ body: String, unit: String = "1/4") -> String {
        "X:1\nT:Rests\nM:4/4\nL:\(unit)\n%%stretchlast 1\nK:C\n\(body)\n"
    }

    /// Every rest on the page, with the measure it stands in.
    private func rests(in layout: ResolvedLayout) -> [(rest: Rest, event: ResolvedEvent,
                                                        measure: ResolvedMeasure)] {
        layout.pages.flatMap(\.systems).flatMap(\.measures).flatMap { measure in
            measure.events.compactMap { event in
                if case .rest(let r) = event.kind { return (r, event, measure) }
                return nil
            }
        }
    }

    /// How far the centre of a rest's drawing lies from the centre of its measure.  Only
    /// for a measure that does not open a system, whose left edge is the bar line before it.
    private func offCentre(_ rest: Rest, _ event: ResolvedEvent, _ measure: ResolvedMeasure)
        throws -> Double {
        let metadata = try BravuraMetadata.load()
        let width = CentredRest.drawnWidth(of: rest, unitNoteLength: measure.unitNoteLength,
                                           metadata: metadata, staffSize: staffSize)
        let left = measure.openingBar?.x ?? measure.origin.x
        return event.origin.x + width / 2 - (left + measure.closingBar.x) / 2
    }

    @Test("A full-measure rest, and a rest lasting a whole measure, stand at its centre",
          arguments: ["Z", "Z1", "z4", "X"])
    func centred(rest: String) throws {
        let found = rests(in: try layout(tune("CDEF | \(rest) | CDEF |]")))
        let (r, event, measure) = try #require(found.first)
        #expect(found.count == 1)
        // A justified bar is far wider than the rest: the left edge would miss by a lot.
        #expect(measure.closingBar.x - measure.origin.x > 8 * staffSize)
        #expect(abs(try offCentre(r, event, measure)) < 0.01)
    }

    @Test("Whether a rest fills the measure is counted in L:", arguments: ["1/8", "1/16"])
    func unitLength(unit: String) throws {
        let length = unit == "1/8" ? 8 : 16
        let found = rests(in: try layout(tune("C\(length) | z\(length) | C\(length) |]",
                                              unit: unit)))
        let (r, event, measure) = try #require(found.first)
        #expect(abs(try offCentre(r, event, measure)) < 0.01)
    }

    @Test("A multi-measure rest's bar is centred too")
    func multiMeasure() throws {
        let found = rests(in: try layout(tune("CDEF | Z6 | CDEF |]")))
        let (r, event, measure) = try #require(found.first)
        #expect(abs(try offCentre(r, event, measure)) < 0.01)
    }

    @Test("A rest shorter than the measure keeps its place, alone or not",
          arguments: ["z2", "z3", "z2 z2", "z3 C"])
    func notCentred(bar: String) throws {
        let found = rests(in: try layout(tune("CDEF | \(bar) | CDEF |]")))
        let (_, event, measure) = try #require(found.first)
        // Where the bar's first note would stand: a notehead's width past the bar line.
        #expect(event.origin.x - measure.origin.x < 2 * staffSize)
    }

    @Test("The meter in force decides, after a change and across a line break")
    func meterInForce() throws {
        let found = rests(in: try layout(tune("CDEF | [M:3/4] CDE | z3 |\nCDE | z3 | z4 |]")))
        try #require(found.count == 3)
        #expect(abs(try offCentre(found[0].rest, found[0].event, found[0].measure)) < 0.01)
        #expect(abs(try offCentre(found[1].rest, found[1].event, found[1].measure)) < 0.01)
        // `z4` overfills a 3/4 bar: it is not a whole measure's rest, and keeps its place.
        #expect(found[2].event.origin.x - found[2].measure.origin.x < 2 * staffSize)
    }

    @Test("A rest after a signature at the head of the bar is centred in what is left")
    func afterSignature() throws {
        let found = rests(in: try layout(tune("CDEF | [M:3/4] z3 | CDE |]")))
        let (r, event, measure) = try #require(found.first)
        let width = CentredRest.drawnWidth(of: r, unitNoteLength: measure.unitNoteLength,
                                           metadata: try BravuraMetadata.load(),
                                           staffSize: staffSize)
        let centre = event.origin.x + width / 2
        // Right of the bar's middle, since the time signature takes its left.
        #expect(centre > (measure.origin.x + measure.closingBar.x) / 2)
        #expect(centre < measure.closingBar.x)
    }

    @Test("On a shared staff, a rest beside another voice's notes keeps its column")
    func sharedStaff() throws {
        let abc = """
            X:1
            T:Shared
            M:4/4
            L:1/4
            %%score (T1 T2)
            %%stretchlast 1
            K:C
            V:T1
            V:T2
            [V:T1] CDEF | z4 | CDEF |]
            [V:T2] CDEF | A,B,CD | CDEF |]
            """
        let found = rests(in: try layout(abc + "\n"))
        let (_, event, measure) = try #require(found.first)
        let notes = measure.events.filter {
            if case .note = $0.kind { return true } else { return false }
        }
        // It stands with the other voice's first note, at the head of the bar.
        let first = try #require(notes.map(\.origin.x).min())
        #expect(abs(event.origin.x - first) < 0.01)
    }

    @Test("A dynamic on a centred rest moves with it")
    func decorationsFollow() throws {
        let score = CeolKitParser().parse(tune("CDEF | !p!Z | CDEF |]"), options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try textProbeRenderer().render(score, diagnostics: &diagnostics).joined()
        let found = rests(in: try layout(tune("CDEF | !p!Z | CDEF |]")))
        let (r, event, measure) = try #require(found.first)
        let width = CentredRest.drawnWidth(of: r, unitNoteLength: measure.unitNoteLength,
                                           metadata: try BravuraMetadata.load(),
                                           staffSize: staffSize)
        let piano = String(SMuFLGlyph.dynamicPiano.character)
        let xs = svg.matches(of: /<text x="([-0-9.]+)"[^>]*>([^<]*)<\/text>/)
            .filter { String($0.2) == piano }
            .compactMap { Double($0.1) }
        let x = try #require(xs.first)
        // Within a glyph's width of the rest's centre, wherever the mark's own anchor is.
        #expect(abs(x - (event.origin.x + width / 2)) < staffSize)
        #expect(abs(try offCentre(r, event, measure)) < 0.01)
    }
}
