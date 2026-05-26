import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

private func sizedMeasure(width: Double) -> SizedMeasure {
    let m = Measure(
        openingBar: nil,
        events: [],
        closingBar: dummyBar,
        endingNumber: nil,
        source: dummyRange
    )
    return SizedMeasure(measure: m, naturalWidth: width, eventOffsets: [])
}

private let usableWidth: Double = 300

// MARK: - Test suite

@Suite struct LineBreakerTests {

    let breaker = LineBreaker()

    // Three measures whose total fits → one system.
    @Test func threeMeasuresFitInOneSystem() {
        let pairs = (0..<3).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 1)
        #expect(systems[0].measures.count == 3)
    }

    // Fourth measure overflows → two systems [3, 1].
    @Test func fourthMeasureOverflows() {
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
        #expect(systems[0].measures.count == 3)
        #expect(systems[1].measures.count == 1)
    }

    // Source-forced break after measure 2 of 4 → two systems [2, 2], first system sourceForced.
    @Test func sourceForcedBreakSplitsCorrectly() {
        let pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] = [
            (sizedMeasure(width: 50), .none),
            (sizedMeasure(width: 50), .hard),
            (sizedMeasure(width: 50), .none),
            (sizedMeasure(width: 50), .none),
        ]
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
        #expect(systems[0].measures.count == 2)
        #expect(systems[0].sourceForced == true)
        #expect(systems[1].measures.count == 2)
    }

    // A single measure wider than usableWidth → one system, no crash.
    @Test func widerThanUsableWidthGetsSingleSystem() {
        let pairs = [(measure: sizedMeasure(width: 500), breakAfter: ScoreLineBreak?.none)]
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 1)
        #expect(systems[0].measures.count == 1)
    }

    // isLastSystem is true only for the final system.
    @Test func isLastSystemOnlyOnFinal() {
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        for (i, system) in systems.enumerated() {
            let shouldBeLast = (i == systems.count - 1)
            #expect(system.isLastSystem == shouldBeLast)
        }
    }

    // Non-source overflow does not set sourceForced.
    @Test func overflowBreakIsNotSourceForced() {
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems[0].sourceForced == false)
    }

    // Empty input → no systems.
    @Test func emptyInputProducesNoSystems() {
        let systems = breaker.breakIntoSystems([], usableWidth: usableWidth)
        #expect(systems.isEmpty)
    }
}
