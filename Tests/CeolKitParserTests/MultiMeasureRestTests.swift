//
//  MultiMeasureRestTests.swift
//  CeolKitParserTests
//
//  Issue #291: a multi-measure rest (`Zn`, ABC v2.2 §4.5) keeps its count of measures, and
//  `Rest.measureCount` reads it whatever `L:` is.
//

import Testing
import CeolKitModel
import CeolKitParser

@Suite("Multi-measure rests (§4.5)")
struct MultiMeasureRestTests {

    private func firstRest(_ body: String, unit: String = "1/8") -> Rest? {
        let abc = "X:1\nT:Test\nM:4/4\nL:\(unit)\nK:C\n\(body)\n"
        for event in parse(abc).score.firstTune?.singleVoiceMeasures.first?.events ?? [] {
            if case .rest(let rest) = event { return rest }
        }
        return nil
    }

    @Test("Z is n measures' rest, whatever the unit note length",
          arguments: [("Z", 1), ("Z1", 1), ("Z6", 6), ("Z12", 12)], ["1/4", "1/8", "1/16"])
    func visible(source: (String, Int), unit: String) throws {
        let rest = try #require(firstRest("\(source.0)|", unit: unit))
        #expect(rest.kind == .fullMeasure)
        #expect(rest.measureCount == source.1)
    }

    @Test("X takes its measures as Z does")
    func invisible() throws {
        let rest = try #require(firstRest("X3|"))
        #expect(rest.kind == .fullMeasureInvisible)
        #expect(rest.measureCount == 3)
    }

    @Test("A rest that is not a full-measure rest has no measure count",
          arguments: ["z8|", "x8|"])
    func ordinary(body: String) throws {
        let rest = try #require(firstRest(body))
        #expect(rest.measureCount == nil)
    }
}
