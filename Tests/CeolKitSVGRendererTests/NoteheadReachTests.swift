import Testing
import CeolKitModel
import CeolKitParser
@testable import CeolKitSVGRenderer

/// Issue #273: the room kept for a note beyond the staff reaches to its notehead's outer
/// edge, not just to its outermost ledger line.
///
/// A head a staff space tall stands half a space past the line or space it is written on, so
/// a note at staff position `p` above the staff reaches `(p - 8) / 2 + ½` spaces over the top
/// line, and the mirror below.  The ledger-line count fell half a space to a space short:
/// `d'` in the issue's tune was given 2 spaces, reached 3, and ran into the title.
@Suite("Notehead reach beyond the staff (#273)")
struct NoteheadReachTests {

    private let config = SVGRenderConfig()

    private func layout(_ body: String) throws -> ResolvedLayout {
        let abc = "X:1\nT:Dynamics\nM:4/4\nL:1/4\nK:C\n\(body) |]\n"
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer(config: config).renderDocument(score).layout
    }

    private func firstSystem(_ body: String) throws -> ResolvedSystem {
        try #require(try layout(body).pages.first?.systems.first)
    }

    @Test("A note above the treble staff is given room to its notehead's top", arguments: [
        ("f", 0.0),    // F5, on the top line: inside the staff
        ("g", 1.0),    // G5, in the space above it
        ("a", 1.5),    // A5, on the first ledger line
        ("c'", 2.5),   // C6, on the second
        ("d'", 3.0),   // D6, in the space above the second
    ])
    func roomAbove(note: String, spaces: Double) throws {
        let system = try firstSystem("\(note)4")
        #expect(abs(system.extraAbove - spaces * config.scaledStaffSize) < 1e-9)
    }

    @Test("A note below the treble staff is given room to its notehead's foot", arguments: [
        ("E", 0.0),    // E4, on the bottom line: inside the staff
        ("D", 1.0),    // D4, in the space below it
        ("C", 1.5),    // C4, on the first ledger line
        ("A,", 2.5),   // A3, on the second
        ("G,", 3.0),   // G3, in the space below the second
    ])
    func roomBelow(note: String, spaces: Double) throws {
        let system = try firstSystem("\(note)4")
        #expect(abs(system.extraBelow - spaces * config.scaledStaffSize) < 1e-9)
    }

    @Test("A high note in the first system stands clear of the title")
    func highNoteClearsTheTitle() throws {
        // The issue's tune.  With nothing above the staff, the top line sits where the title
        // block ends, a music space below the title.  The d' must reach no higher than that.
        let s = config.scaledStaffSize
        let high = try firstSystem("B,/ G/ d'/ c'/")
        let plain = try firstSystem("B,/ G/ d/ c/")
        let plainTop = plain.origin.y + plain.staffOrigin
        let headTop = high.origin.y + high.staffOrigin - 3 * s
        #expect(plain.extraAbove == 0)
        #expect(abs(headTop - plainTop) < 1e-9)
    }
}
