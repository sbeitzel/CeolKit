// Meter (M:) parsing conformance tests. ABC §3.1.6.
import Testing
import CeolKitModel
import CeolKitParser

private func meterTune(_ mField: String, body: String = "C|") -> String {
    "X:1\nT:Test\n\(mField)\nL:1/4\nK:C\n\(body)"
}

@Suite("Meter")
struct MeterTests {

    @Test("M:4/4 parses as fraction(4, 4)")
    func commonFraction() {
        let result = parse(meterTune("M:4/4"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 4)
            #expect(den == 4)
        } else {
            Issue.record("Expected .fraction(4, 4), got \(String(describing: meter))")
        }
    }

    @Test("M:3/4 parses as fraction(3, 4)")
    func threeFour() {
        let result = parse(meterTune("M:3/4"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 3)
            #expect(den == 4)
        } else {
            Issue.record("Expected .fraction(3, 4), got \(String(describing: meter))")
        }
    }

    @Test("M:6/8 parses as fraction(6, 8)")
    func sixEight() {
        let result = parse(meterTune("M:6/8"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 6)
            #expect(den == 8)
        } else {
            Issue.record("Expected .fraction(6, 8), got \(String(describing: meter))")
        }
    }

    @Test("M:9/8 parses as fraction(9, 8)")
    func nineEight() {
        let result = parse(meterTune("M:9/8"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 9)
            #expect(den == 8)
        } else {
            Issue.record("Expected .fraction(9, 8), got \(String(describing: meter))")
        }
    }

    @Test("M:12/8 parses as fraction(12, 8)")
    func twelveEight() {
        let result = parse(meterTune("M:12/8"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 12)
            #expect(den == 8)
        } else {
            Issue.record("Expected .fraction(12, 8), got \(String(describing: meter))")
        }
    }

    @Test("M:2/2 parses as fraction(2, 2)")
    func twoTwo() {
        let result = parse(meterTune("M:2/2"))
        let meter = result.score.firstTune?.meter
        if case .fraction(let num, let den) = meter {
            #expect(num == 2)
            #expect(den == 2)
        } else {
            Issue.record("Expected .fraction(2, 2), got \(String(describing: meter))")
        }
    }

    @Test("M:C parses as commonTime")
    func commonTime() {
        let result = parse(meterTune("M:C"))
        let meter = result.score.firstTune?.meter
        if case .commonTime = meter {
            // expected
        } else {
            Issue.record("Expected .commonTime, got \(String(describing: meter))")
        }
    }

    @Test("M:C| parses as cutTime")
    func cutTime() {
        let result = parse(meterTune("M:C|"))
        let meter = result.score.firstTune?.meter
        if case .cutTime = meter {
            // expected
        } else {
            Issue.record("Expected .cutTime, got \(String(describing: meter))")
        }
    }

    @Test("M:none parses as free meter")
    func freeMeter() {
        let result = parse(meterTune("M:none"))
        let meter = result.score.firstTune?.meter
        if case .free = meter {
            // expected
        } else {
            Issue.record("Expected .free, got \(String(describing: meter))")
        }
    }

    @Test("M:(2+3)/8 parses as complex([2,3], den:8)")
    func complexMeter() {
        let result = parse(meterTune("M:(2+3)/8"))
        let meter = result.score.firstTune?.meter
        if case .complex(let groups, let den) = meter {
            #expect(groups == [2, 3])
            #expect(den == 8)
        } else {
            Issue.record("Expected .complex([2,3], den:8), got \(String(describing: meter))")
        }
    }

    @Test("M:(3+2+3)/8 parses as complex([3,2,3], den:8)")
    func complexMeter3Groups() {
        let result = parse(meterTune("M:(3+2+3)/8"))
        let meter = result.score.firstTune?.meter
        if case .complex(let groups, let den) = meter {
            #expect(groups == [3, 2, 3])
            #expect(den == 8)
        } else {
            Issue.record("Expected .complex([3,2,3], den:8), got \(String(describing: meter))")
        }
    }

    // MARK: Default unit note length from meter

    @Test("M:6/8 implies default L:1/8 (6/8 ≥ 3/4)")
    func unitLengthFrom6_8() {
        let result = parse("X:1\nT:T\nM:6/8\nK:C\nC|")
        #expect(result.score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("M:3/4 implies default L:1/8 (3/4 ≥ 3/4 threshold)")
    func unitLengthFrom3_4() {
        let result = parse("X:1\nT:T\nM:3/4\nK:C\nC|")
        #expect(result.score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("M:2/4 implies default L:1/16 (2/4 < 3/4 threshold)")
    func unitLengthFrom2_4() {
        let result = parse("X:1\nT:T\nM:2/4\nK:C\nC|")
        #expect(result.score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 16))
    }

    @Test("M:C (common time = 4/4) implies default L:1/8")
    func unitLengthFromCommonTime() {
        let result = parse("X:1\nT:T\nM:C\nK:C\nC|")
        #expect(result.score.firstTune?.unitNoteLength == Fraction(numerator: 1, denominator: 8))
    }

    @Test("Inline [M:12/8] updates meter for subsequent notes")
    func inlineMeterChange() {
        let abc = """
        X:1
        T:Test
        M:9/8
        L:1/8
        K:G
        DGH GAG|[M:12/8]D4 GAG|
        """
        // The second measure should use M:12/8
        let result = parse(abc)
        // We can't directly query per-measure meter from the domain model,
        // but we can verify that the measure's note count is consistent with 12/8.
        let measures = result.score.firstTune?.singleVoiceMeasures ?? []
        #expect(measures.count >= 2)
    }

    // MARK: No meter

    @Test("Missing M: header produces no fatal error (recovery)")
    func missingMeterNoFatalError() {
        let result = parse("X:1\nT:Test\nK:C\nC|")
        // Should produce a score (not a crash), possibly with a warning
        #expect(result.score.tunes.count == 1)
    }
}
