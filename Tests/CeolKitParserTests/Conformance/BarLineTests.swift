// Bar line and repeat symbol conformance tests. ABC §4.8.
import Testing
import CeolKitModel
import CeolKitParser

private func barTune(_ body: String) -> String {
    "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(body)"
}

@Suite("Bar Lines and Repeats")
struct BarLineTests {

    // MARK: Basic bar lines

    @Test("| produces a single bar line")
    func singleBar() {
        let result = parse(barTune("CDEF|CDEF|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        guard !measures.isEmpty else {
            Issue.record("Expected measures in score, got none")
            return
        }
        #expect(measures[0].closingBar.kind == .single)
    }

    @Test("|| produces a double bar line")
    func doubleBar() {
        let result = parse(barTune("CDEF||CDEF|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let hasDouble = measures.contains { $0.closingBar.kind == .double }
        #expect(hasDouble)
    }

    @Test("|] produces a final bar line")
    func finalBar() {
        let result = parse(barTune("CDEF|]"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let lastMeasure = measures.last
        #expect(lastMeasure?.closingBar.kind == .final)
    }

    @Test("[| produces a start-repeat-section bar line")
    func startSectionBar() {
        let result = parse(barTune("[|CDEF|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let hasStart = measures.contains {
            $0.openingBar?.kind == .start || $0.closingBar.kind == .start
        }
        #expect(hasStart)
    }

    // MARK: Repeat bars

    @Test("|: produces a repeat-start bar line")
    func repeatStart() {
        let result = parse(barTune("|:CDEF:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let hasStart = measures.contains {
            $0.openingBar?.kind == .repeatStart || $0.closingBar.kind == .repeatStart
        }
        #expect(hasStart)
    }

    @Test(":| produces a repeat-end bar line")
    func repeatEnd() {
        let result = parse(barTune("CDEF:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let hasEnd = measures.contains { $0.closingBar.kind == .repeatEnd }
        #expect(hasEnd)
    }

    @Test(":: produces a repeat-both bar line (end one repeat, start another)")
    func repeatBoth() {
        let result = parse(barTune("|:CDEF::GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let hasBoth = measures.contains { $0.closingBar.kind == .repeatBoth }
        #expect(hasBoth)
    }

    // MARK: Variant endings

    @Test("|1 marks measure as first ending")
    func firstEnding() {
        let result = parse(barTune("|:CDEF|1CDEF:|2GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let ending1 = measures.first(where: { m in m.endings.contains { $0.numbers.contains(1) } })
        #expect(ending1 != nil)
    }

    @Test("|2 marks measure as second ending")
    func secondEnding() {
        let result = parse(barTune("|:CDEF|1CDEF:|2GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let ending2 = measures.first(where: { m in m.endings.contains { $0.numbers.contains(2) } })
        #expect(ending2 != nil)
    }

    @Test("[1 bracket form also marks first ending")
    func bracketFirstEnding() {
        let result = parse(barTune("|:CDEF[1CDEF:|[2GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let ending1 = measures.first(where: { m in m.endings.contains { $0.numbers.contains(1) } })
        #expect(ending1 != nil)
    }

    /// `|1` is a bar line *and* an ending number.  The lexer used to read the digit in
    /// place of the bar, which merged the measure before the ending into the ending itself
    /// and lost one bar from every repeat written this way — §14.4 among them.
    @Test("|1 closes the measure before the ending as well as opening it")
    func endingNumberDoesNotSwallowItsBarLine() {
        let result = parse(barTune("CDEF|GABC|1CDEF:|2GABC|]"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 4)
        #expect(measures.count(where: { !$0.endings.isEmpty }) == 2)
        // The bar that the ending number followed keeps its own closing bar line.
        guard measures.count == 4 else { return }
        #expect(measures[1].closingBar.kind == .single)
        #expect(measures[1].endings.isEmpty)
        #expect(measures[2].endings.map(\.numbers) == [[1]])
    }

    @Test("|1,2 and |1-3 keep their bar line and their whole list")
    func endingListsKeepTheirBarLine() {
        for (body, expected) in [("CDEF|1,2 GABC|]", [1, 2]), ("CDEF|1-3 GABC|]", [1, 2, 3])] {
            let measures = parse(barTune(body)).score.firstTune?.singleVoiceMeasures ?? []
            #expect(measures.count == 2, "\(body) gave \(measures.count) measures")
            #expect(measures.last?.endings.map(\.numbers) == [expected])
        }
    }

    /// §4.10 ties only the end of an ending to a bar line, so a bare `[1` may stand part
    /// way through a bar — and the measure has to say where, or the bracket starts at the
    /// bar line instead of the note (#172).
    @Test("[1 in mid-measure records the event the ending starts at")
    func midMeasureEndingRecordsItsStart() {
        let measures = parse(barTune("|:CDEF|GA[1 B c:|[2 d4|]")).score.firstTune?
            .singleVoiceMeasures ?? []
        #expect(measures.count == 3)
        guard measures.count == 3 else { return }
        #expect(measures[1].endings.map(\.numbers) == [[1]])
        // `G`, `A` — then the ending, which opens at the space before `B`.
        let start = measures[1].endings.first?.startIndex
        #expect(start == 2)
        let firstNote = measures[1].events.dropFirst(start ?? 0).first {
            if case .note = $0 { return true }
            return false
        }
        if case .note(let n)? = firstNote {
            #expect(n.pitch.step == .b)
        } else {
            Issue.record("no note after the ending start")
        }
        // `[2` written against the bar line starts where `:|2` would: at the bar.
        #expect(measures[2].endings == [VariantEnding(numbers: [2], startIndex: nil)])
    }

    @Test("Endings written at a bar line start at the bar", arguments: [
        "|:CDEF|1GABc:|2CDEF|]",
        "|:CDEF|[1GABc:|[2CDEF|]",
        "|:CDEF| [1 GABc:| [2 CDEF|]",
    ])
    func barLineEndingsHaveNoStartIndex(body: String) {
        let measures = parse(barTune(body)).score.firstTune?.singleVoiceMeasures ?? []
        let endings = measures.flatMap(\.endings)
        #expect(endings.count == 2)
        #expect(endings.allSatisfy { $0.startIndex == nil })
    }

    /// A bar whose variants differ only in its second half: the music before `[1` is
    /// played every time, and each ending runs on to the next — one measure, two endings.
    @Test("Two endings in one bar are both kept, each where it starts")
    func twoEndingsInOneMeasure() {
        let body = "|{gcd}c2{g}B<{d}A [1 {g}B2{g}c<e [2 {g}B>e{g}A>B |"
        let measures = parse(barTune(body)).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count == 1)
        guard let measure = measures.first else { return }
        #expect(measure.endings.map(\.numbers) == [[1], [2]])
        let starts = measure.endings.compactMap(\.startIndex)
        #expect(starts.count == 2)
        guard starts.count == 2 else { return }
        // Each ending starts at the grace group before its `B`.
        for start in starts {
            if case .grace? = measure.events.dropFirst(start).first(where: {
                if case .spacer = $0 { return false }
                return true
            }) {} else {
                Issue.record("ending at \(start) does not start at a grace group")
            }
        }
        #expect(starts[0] < starts[1])
    }

    @Test("A second ending with no music since the first replaces it", arguments: [
        "|:CDEF|[1 [2 GABc|]",
        "|:CDEF|GA [1 [2 Bc|]",
    ])
    func emptyEndingIsReplaced(body: String) {
        let measures = parse(barTune(body)).score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.last?.endings.map(\.numbers) == [[2]])
    }

    /// The voice's last bar is closed by the end of the music rather than a bar line, and
    /// used to be built with no endings at all (#246).
    @Test("An ending in a last bar with no closing bar line is kept", arguments: [
        ("|:CDEF|1GABc:|2CDEF", [[2]], false),
        ("|:CDEF|GA [1 Bc:|[2 CDEF", [[2]], false),
        ("|:CDEF|GA [1 Bc [2 dc", [[1], [2]], true),
    ])
    func endingInUnclosedLastBar(body: String, numbers: [[Int]], midBar: Bool) {
        let measures = parse(barTune(body)).score.firstTune?.singleVoiceMeasures ?? []
        let endings = measures.last?.endings ?? []
        #expect(endings.map(\.numbers) == numbers, "\(body)")
        #expect(endings.allSatisfy { ($0.startIndex != nil) == midBar }, "\(body)")
    }

    @Test("Measures without ending numbers have no endings")
    func noEndingNumber() {
        let result = parse(barTune("CDEF|GABC|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        for measure in measures {
            #expect(measure.endings.isEmpty)
        }
    }

    // MARK: Anacrusis (pickup bar)

    @Test("D|CDEF| — D is an anacrusis measure with nil openingBar")
    func anacrusis() {
        let result = parse(barTune("D|CDEF|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        guard let first = measures.first else { Issue.record("Parser prerequisite not met"); return }
        #expect(first.openingBar == nil)
        #expect(first.noteEvents.count == 1)
        #expect(first.noteEvents.first?.pitch.step == .d)
    }

    @Test("Full measure has non-nil openingBar or is the first measure")
    func fullMeasureStructure() {
        let result = parse(barTune("CDEF|GABC|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        guard measures.count >= 2 else { Issue.record("Parser prerequisite not met"); return }
        // Second measure must have an openingBar
        #expect(measures[1].openingBar != nil)
    }

    // MARK: Measure event counts

    @Test("4/4 measure with 4 quarter notes has 4 events")
    func fourQuarterNotes() {
        let result = parse(barTune("CDEF|"))
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count == 4)
    }

    @Test("3/4 measure with 3 quarter notes has 3 events")
    func threeQuarterNotes() {
        let result = parse("X:1\nT:T\nM:3/4\nL:1/4\nK:C\nCDE|")
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count == 3)
    }
}
