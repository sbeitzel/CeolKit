//
//  BarNumberTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #290: `%%barnumbers` / `%%measurenb`, `%%measurefirst` and `%%measurebox` (ABC v2.2
//  §11.4.4), drawn as abcm2ps 8.14 draws them.
//

import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// What `%%barnumbers` puts on the page, read out of the emitted SVG.
///
/// The expected numbers are the ones `abcm2ps -g` prints for the same source: the count is
/// abcm2ps's (`set_bar_num` in `parse.c`) and so is where each number goes (`draw_measnb`
/// in `deco.c`).
@Suite("Bar numbers")
struct BarNumberTests {

    private struct Number {
        let text: String
        let x: Double
        let y: Double
    }

    private func render(_ abc: String, config: SVGRenderConfig = SVGRenderConfig())
        throws -> (svg: String, numbers: [Number], staves: [SystemGeometry]) {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let pages = try textProbeRenderer(config).render(score, diagnostics: &diagnostics)
        let svg = pages.joined()
        // Bar numbers are the only italic text made of digits alone.
        let numbers = svg.matches(
            of: /<text x="([-0-9.]+)" y="([-0-9.]+)"[^>]*font-style="italic"[^>]*>([0-9]+)<\/text>/
        ).compactMap { match -> Number? in
            guard let x = Double(match.1), let y = Double(match.2) else { return nil }
            return Number(text: String(match.3), x: x, y: y)
        }
        return (svg, numbers, try SVGGeometry.pages(from: pages).flatMap(\.systems))
    }

    /// A tune with a pickup, a `|1 … :|2` ending and a `Z4`, over four systems.
    private func tune(_ directives: String) -> String {
        """
        \(directives)
        X:1
        T:Numbers
        M:4/4
        L:1/8
        K:D
        d2|ABcd efga|bagf edcB|A2A2 B2B2|c4 d4|e8|f8|g8|a8|
        ABcd efga|bagf edcB|A2A2 B2B2|c4 d4|e8|f8|g8|a8|
        |:ABcd efga|bagf edcB|1 A2A2 B2B2:|2 c4 d4|
        Z4|ABcd efga|bagf edcB|A2A2 B2B2|c4 d4|]

        """
    }

    // MARK: - Which bars

    @Test("No numbers unless the document asks for them")
    func offByDefault() throws {
        #expect(try render(tune("")).numbers.isEmpty)
        #expect(try render(tune("%%barnumbers -1")).numbers.isEmpty)
    }

    /// The pickup is not bar 1, the `|2` ending restarts from where `|1` began (bar 19, so
    /// the bar after it is 20), and `Z4` is four bars.
    @Test("Every fourth bar, counted as abcm2ps counts")
    func everyFourth() throws {
        #expect(try render(tune("%%barnumbers 4")).numbers.map(\.text)
                == ["4", "8", "12", "16", "20", "24"])
    }

    @Test("%%measurenb 0 numbers the head of every system but the first")
    func systemStarts() throws {
        let (_, numbers, staves) = try render(tune("%%measurenb 0"))
        #expect(numbers.map(\.text) == ["9", "17", "20"])
        // At the left edge of the system, over the clef.
        for (number, staff) in zip(numbers, staves.dropFirst()) {
            #expect(abs(number.x - staff.left) < 1e-6)
            #expect(number.y < staff.topY)
        }
    }

    @Test("%%measurefirst sets the first bar's number, and the first system can carry it")
    func measureFirst() throws {
        let abc = """
        %%barnumbers 2
        %%measurefirst 10
        X:1
        T:First
        M:3/4
        L:1/4
        K:G
        g a b|d' c' b|e2 e|c3|[M:2/4]c d|e f|g2|a2|
        B,C D|E F|G2|A2|]

        """
        // abcm2ps prints exactly these for this source, across the meter change.
        #expect(try render(abc).numbers.map(\.text) == ["10", "12", "14", "16", "18", "20"])
    }

    /// The two halves of a bar split by a repeat sign are one bar.
    @Test("A bar line closing less than a measure does not count")
    func incompleteBarsDoNotCount() throws {
        let abc = "%%barnumbers 1\nX:1\nT:Split\nM:4/4\nL:1/4\nK:C\nCDEF|GA:|Bc|defg|]\n"
        #expect(try render(abc).numbers.map(\.text) == ["2", "3"])
    }

    @Test("A tune with no meter counts every bar line")
    func freeMeter() throws {
        let abc = "%%barnumbers 1\nX:1\nT:Free\nM:none\nL:1/4\nK:C\nCD|EFG|A|Bc|]\n"
        #expect(try render(abc).numbers.map(\.text) == ["2", "3", "4"])
    }

    @Test("The final bar line is not numbered")
    func finalBarIsNotNumbered() throws {
        let abc = "%%barnumbers 1\nX:1\nT:End\nM:4/4\nL:1/4\nK:C\nCDEF|GABc|]\n"
        #expect(try render(abc).numbers.map(\.text) == ["2"])
    }

    @Test("A %%barnumbers in the tune body governs the whole tune")
    func bodyDirective() throws {
        let abc = "X:1\nT:Body\nM:4/4\nL:1/4\nK:C\nCDEF|GABc|\n%%barnumbers 1\ncBAG|FEDC|]\n"
        // Bar 3 opens the second system, so it is numbered at its head.
        #expect(try render(abc).numbers.map(\.text) == ["2", "3", "4"])
    }

    // MARK: - Where

    @Test("A number stands over its bar line, clear of the staff")
    func placement() throws {
        let (_, numbers, staves) = try render(tune("%%barnumbers 4"))
        guard let four = numbers.first, let staff = staves.first else {
            Issue.record("nothing drawn"); return
        }
        let u = staff.staffLineGap / TextStyles.nominalStaffSize
        // abcm2ps: the baseline at least 8 units above the top line …
        #expect(four.y <= staff.topY - 8 * u + 1e-6)
        // … and the number 0.4 of its width left of its bar line, so the line passes
        // under it.
        #expect(staff.barlineXs.contains { $0 > four.x && $0 < four.x + 2 * staff.staffLineGap })
    }

    @Test("A number is raised over a high note right after its bar line")
    func raisedOverHighNote() throws {
        // Bar 2 opens on c''' — two ledger lines above the staff.
        let low = "%%barnumbers 1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF|GABc|cBAG|]\n"
        let high = "%%barnumbers 1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\nCDEF|c'BAG|cBAG|]\n"
        // Measured up from the top staff line: the staff itself moves down to make room.
        func height(_ abc: String) throws -> Double? {
            let (_, numbers, staves) = try render(abc)
            guard let number = numbers.first, let staff = staves.first else { return nil }
            return staff.topY - number.y
        }
        guard let lowHeight = try height(low), let highHeight = try height(high) else {
            Issue.record("nothing drawn"); return
        }
        #expect(highHeight > lowHeight)
    }

    @Test("Only the top staff of a system carries numbers")
    func topStaffOnly() throws {
        let abc = """
        %%barnumbers 1
        X:1
        T:Two
        M:4/4
        L:1/4
        V:1
        V:2 clef=bass
        K:C
        V:1
        CDEF|GABc|cBAG|]
        V:2
        C,D,E,F,|G,A,B,C|CB,A,G,|]

        """
        let (_, numbers, staves) = try render(abc)
        #expect(numbers.map(\.text) == ["2", "3"])
        guard let top = staves.first else { Issue.record("nothing drawn"); return }
        #expect(numbers.allSatisfy { $0.y < top.topY })
    }

    @Test("%%measurebox draws a box around each number")
    func boxed() throws {
        let plain = try render(tune("%%barnumbers 4"))
        let boxed = try render(tune("%%barnumbers 4\n%%measurebox 1"))
        #expect(boxed.numbers.map(\.text) == plain.numbers.map(\.text))
        let rects = boxed.svg.matches(of: /<rect x="([-0-9.]+)" y="([-0-9.]+)" width="([-0-9.]+)" height="([-0-9.]+)" fill="none" stroke="black"/)
            .compactMap { m -> (x: Double, y: Double, w: Double, h: Double)? in
                guard let x = Double(m.1), let y = Double(m.2),
                      let w = Double(m.3), let h = Double(m.4) else { return nil }
                return (x, y, w, h)
            }
        for number in boxed.numbers {
            #expect(rects.contains {
                $0.x < number.x && number.x < $0.x + $0.w && $0.y < number.y && number.y < $0.y + $0.h
            }, "no box around \(number.text)")
        }
    }

    @Test("Chord symbols stand above the bar numbers")
    func chordSymbolsClearNumbers() throws {
        let abc = "%%barnumbers 1\nX:1\nT:T\nM:4/4\nL:1/4\nK:C\n\"C\"CDEF|\"G\"GABc|cBAG|]\n"
        let (svg, numbers, _) = try render(abc)
        let chords = svg.matches(of: /<text x="[-0-9.]+" y="([-0-9.]+)"[^>]*>([CG])<\/text>/)
            .compactMap { Double($0.1) }
        guard let two = numbers.first, let chord = chords.max() else {
            Issue.record("nothing drawn"); return
        }
        let style = TextStyles.standard(staffSize: SVGRenderConfig().staffSize * 0.75).barNumber
        // The chord symbol's baseline is above the top of the number's digits.
        #expect(chord < two.y - style.size * LibertinusSerifMetrics.capHeightRatio)
    }
}
