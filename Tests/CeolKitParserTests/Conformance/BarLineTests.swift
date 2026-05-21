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
        let ending1 = measures.first(where: { $0.endingNumber?.contains(1) == true })
        #expect(ending1 != nil)
    }

    @Test("|2 marks measure as second ending")
    func secondEnding() {
        let result = parse(barTune("|:CDEF|1CDEF:|2GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let ending2 = measures.first(where: { $0.endingNumber?.contains(2) == true })
        #expect(ending2 != nil)
    }

    @Test("[1 bracket form also marks first ending")
    func bracketFirstEnding() {
        let result = parse(barTune("|:CDEF[1CDEF:|[2GABC:|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        let ending1 = measures.first(where: { $0.endingNumber?.contains(1) == true })
        #expect(ending1 != nil)
    }

    @Test("Measures without ending numbers have nil endingNumber")
    func noEndingNumber() {
        let result = parse(barTune("CDEF|GABC|"))
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        for measure in measures {
            #expect(measure.endingNumber == nil)
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
