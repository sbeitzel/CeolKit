import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #268: the room an accidental needs is kept in front of its note, where it is drawn,
/// not after it.
///
/// The sizer added the accidental's width to the column *after* the note, so the accidental
/// ran into the bar line or note before it, and the gap after the altered note was wider
/// than any other.  abcm2ps puts it in the note's left width (`set_width`, `music.c`).
@Suite("Accidental spacing (#268)")
struct AccidentalSpacingTests {

    private enum Kind: Equatable { case head, accidental, grace, bar }
    private struct Mark { let x: Double; let kind: Kind }

    private let config = SVGRenderConfig()

    /// The noteheads, accidentals and bar lines of `body`'s one unstretched staff, left to
    /// right.
    private func marks(_ body: String, header: String = "") throws -> [Mark] {
        let abc = "%%stretchstaff 0\nX:1\nT:Bar\nM:2/4\nL:1/8\n\(header)K:C\n\(body)\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        let svg = try textProbeRenderer(config).render(score).joined()

        let accidentals: Set<Character> = [
            SMuFLGlyph.accidentalSharp.character, SMuFLGlyph.accidentalFlat.character,
            SMuFLGlyph.accidentalNatural.character, SMuFLGlyph.accidentalDoubleSharp.character,
        ]
        let fullSize = String(format: "%g", 4 * config.scaledStaffSize)
        var found: [Mark] = svg.matches(
            of: /<text x="([-0-9.]+)" y="[-0-9.]+" font-family="Bravura" font-size="([0-9.]+)"[^>]*>(.)<\/text>/
        ).compactMap { m in
            guard let x = Double(m.1), let glyph = String(m.3).first else { return nil }
            let isFullSize = String(m.2) == fullSize
            if glyph == SMuFLGlyph.noteheadBlack.character || glyph == SMuFLGlyph.noteheadHalf.character {
                return Mark(x: x, kind: isFullSize ? .head : .grace)
            }
            if accidentals.contains(glyph) && isFullSize { return Mark(x: x, kind: .accidental) }
            return nil
        }
        let staffHeight = 4 * config.scaledStaffSize
        found += svg.matches(
            of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)"/
        ).compactMap { m in
            guard let x1 = Double(m.1), let y1 = Double(m.2), let x2 = Double(m.3),
                  let y2 = Double(m.4), x1 == x2, abs(abs(y2 - y1) - staffHeight) < 0.01
            else { return nil }
            return Mark(x: x1, kind: .bar)
        }
        return found.sorted { $0.x < $1.x }
    }

    private func xs(_ marks: [Mark], _ kind: Kind) -> [Double] {
        marks.filter { $0.kind == kind }.map(\.x)
    }

    @Test("An accidental after a bar line stands where a plain note's head would")
    func accidentalTakesTheHeadsPlaceAfterTheBar() throws {
        // Bar 2 opens with a plain c, bar 3 with ^c: the sharp is as far from its bar line as
        // the c is from its own.
        let found = try marks("c2 c2 | c2 c2 | ^c2 c2 |]")
        let bars = xs(found, .bar)
        let heads = xs(found, .head)
        let sharp = try #require(xs(found, .accidental).first)
        try #require(bars.count >= 2 && heads.count == 6)
        let plainLead = heads[2] - bars[0]
        #expect(abs((sharp - bars[1]) - plainLead) < 0.01)
        #expect(heads[4] > sharp)
    }

    @Test("The space after an altered note is the space after a plain one")
    func noExtraRoomAfterTheAlteredNote() throws {
        let found = try marks("c2 c2 | ^c2 c2 | _B2 B2 | ^^c2 =c2 |]")
        let heads = xs(found, .head)
        try #require(heads.count == 8)
        let plain = heads[1] - heads[0]
        for altered in [2, 4] {
            #expect(abs((heads[altered + 1] - heads[altered]) - plain) < 0.01)
        }
        // =c after ^^c: the natural stands a plain column after the ^^c, and the c after it.
        let natural = try #require(found.last { $0.kind == .accidental }?.x)
        #expect(abs((natural - heads[6]) - plain) < 0.01)
        #expect(heads[7] > natural)
    }

    @Test("Close-set accidentals stand clear of the note before them")
    func accidentalsClearThePreviousHead() throws {
        let found = try marks("ab^c^d ^e^f^g^a |]", header: "L:1/16\n")
        let headWidth = 1.18 * config.scaledStaffSize  // Bravura noteheadBlack
        var lastHead: Double?
        for mark in found {
            switch mark.kind {
            case .head: lastHead = mark.x
            case .accidental:
                let previous = try #require(lastHead)
                #expect(mark.x > previous + headWidth)
            default: break
            }
        }
    }

    @Test("A grace note's principal keeps its accidental between the two")
    func accidentalStandsBetweenGraceAndNote() throws {
        let found = try marks("{g}^c2 c2 c2 c2 |]")
        let grace = try #require(xs(found, .grace).first)
        let sharp = try #require(xs(found, .accidental).first)
        let head = try #require(xs(found, .head).first)
        #expect(grace < sharp && sharp < head)
    }

    @Test("On a shared staff, an accidental is kept in front of the column")
    func sharedStaffAccidentalInFront() throws {
        // Bar 1 is plain; bar 2 opens with ^c in the upper voice over A, in the lower.
        let header = "%%score (1 2)\nV:1\nV:2\n"
        let found = try marks("[V:1] c2 c2 | ^c2 c2 |]\n[V:2] A,2 A,2 | A,2 A,2 |]", header: header)
        let bars = xs(found, .bar)
        let sharp = try #require(xs(found, .accidental).first)
        let heads = xs(found, .head)
        try #require(bars.count >= 1 && heads.count == 8)
        // The voices' heads pair up, column by column: [c A,] [c A,] | [^c A,] [c A,].
        let columns = stride(from: 0, to: 8, by: 2).map { heads[$0] }
        // The sharp stands where bar 1's first heads stand from the head of the staff:
        // clear of the bar line, and in front of its own note.
        #expect(sharp > bars[0] + 0.5 * config.scaledStaffSize)
        #expect(sharp < columns[2])
        // And no room is left over after the altered column.
        #expect(abs((columns[3] - columns[2]) - (columns[1] - columns[0])) < 0.01)
    }
}
