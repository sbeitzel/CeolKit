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

    // Issue #40: a 4-measure stave that needs two systems is split evenly, not 3 + orphan.
    @Test func fourthMeasureOverflowsAndSystemsAreBalanced() {
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
        #expect(systems[0].measures.count == 2)
        #expect(systems[1].measures.count == 2)
    }

    // Balancing never adds a system: the greedy minimum is what gets rebalanced.
    @Test func balancingKeepsTheGreedySystemCount() {
        // 5 × 90 = 450 over a 300 pt line: two systems minimum, split 3 + 2.
        let pairs = (0..<5).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
        #expect(systems[0].measures.count == 3)
        #expect(systems[1].measures.count == 2)
    }

    // Balancing is per stave: measures never migrate across a source-forced break.
    @Test func balancingDoesNotMoveMeasuresAcrossSourceBreaks() {
        // Stave 1: four 90 pt measures (needs two systems). Stave 2: one 90 pt measure.
        var pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] =
            (0..<3).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        pairs.append((measure: sizedMeasure(width: 90), breakAfter: .hard))
        pairs.append((measure: sizedMeasure(width: 90), breakAfter: nil))

        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 3)
        #expect(systems[0].measures.count == 2)
        #expect(systems[1].measures.count == 2)
        #expect(systems[1].sourceForced == true)
        #expect(systems[2].measures.count == 1)
    }

    // Only systems from a stave the breaker had to split are marked as such.
    @Test func staveWasSplitMarksOnlyTheSplitStave() {
        var pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] =
            (0..<3).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        pairs.append((measure: sizedMeasure(width: 90), breakAfter: .hard))
        pairs.append((measure: sizedMeasure(width: 90), breakAfter: nil))

        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems[0].staveWasSplit == true)
        #expect(systems[1].staveWasSplit == true)
        #expect(systems[2].staveWasSplit == false)
    }

    // MARK: - Overflow tolerance

    // A stave that overruns the line by less than the tolerance stays whole; the justifier
    // compresses it rather than the breaker orphaning the last measure.
    @Test func slightOverflowIsToleratedRatherThanBroken() {
        // 4 × 75.75 = 303 pt on a 300 pt line — 1% over, inside the 2% default.
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 75.75), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 1)
        #expect(systems[0].measures.count == 4)
    }

    // Past the tolerance the line breaks as usual.
    @Test func overflowBeyondToleranceStillBreaks() {
        // 4 × 78 = 312 pt on a 300 pt line — 4% over, outside the 2% default.
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 78), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
    }

    // Zero tolerance restores strict first-fit at the line boundary.
    @Test func zeroToleranceBreaksOnAnyOverflow() {
        let strict = LineBreaker(overflowTolerance: 0)
        let pairs = (0..<4).map { _ in (measure: sizedMeasure(width: 75.75), breakAfter: ScoreLineBreak?.none) }
        let systems = strict.breakIntoSystems(pairs, usableWidth: usableWidth)
        #expect(systems.count == 2)
    }

    // MARK: - Header widths

    // The first system has less room for music, so packing must account for it.
    @Test func firstSystemHeaderWidthReducesItsCapacity() {
        // Three 90 pt measures fit a bare 300 pt line, but not one with a 60 pt header.
        let pairs = (0..<3).map { _ in (measure: sizedMeasure(width: 90), breakAfter: ScoreLineBreak?.none) }
        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                               firstSystemHeaderWidth: 60,
                                               laterSystemHeaderWidth: 20)
        #expect(systems.count == 2)
        // Whatever the balance, no system may exceed its own capacity plus the tolerance.
        let capacities = [usableWidth - 60, usableWidth - 20]
        for (system, capacity) in zip(systems, capacities) {
            let natural = system.measures.reduce(0.0) { $0 + $1.naturalWidth }
            #expect(natural <= capacity * 1.02)
        }
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

    // MARK: - Joint breaking (issue #58)

    private func voiceLine(widths: [Double]) -> LineBreaker.VoiceLine {
        LineBreaker.VoiceLine(measures: widths.map(sizedMeasure(width:)))
    }

    // Every voice breaks at the same measure index, or the staves desynchronise.
    @Test func voicesBreakAtTheSameMeasureIndex() {
        let voices = [voiceLine(widths: [90, 90, 90, 90]), voiceLine(widths: [90, 90, 90, 90])]
        let groups = breaker.breakIntoGroups(voices, breaks: [nil, nil, nil, nil],
                                             usableWidth: usableWidth)
        #expect(groups.count == 2)
        for group in groups {
            #expect(group.staves.count == 2)
            #expect(group.staves.map(\.measures.count) == [2, 2])
        }
    }

    // A column is as wide as its widest voice, so the break has to be driven by the max —
    // not by either voice on its own, which would let a system overrun the line.
    @Test func columnWidthIsTheMaxAcrossVoices() {
        // Voice 1 alone would fit 3 columns of 60 on a 300 pt line alongside a 90; voice 2
        // makes two of those columns 150 wide, so only two columns fit.
        let voices = [voiceLine(widths: [90, 60, 60]), voiceLine(widths: [90, 150, 150])]
        let groups = breaker.breakIntoGroups(voices, breaks: [nil, nil, nil],
                                             usableWidth: usableWidth)
        #expect(groups.map(\.columnCount) == [2, 1])
    }

    // A .hard break closes the system in every voice at once.
    @Test func sourceBreakClosesTheWholeGroup() {
        let voices = [voiceLine(widths: [50, 50, 50]), voiceLine(widths: [50, 50, 50])]
        let groups = breaker.breakIntoGroups(voices, breaks: [nil, .hard, nil],
                                             usableWidth: usableWidth)
        #expect(groups.map(\.columnCount) == [2, 1])
        #expect(groups[0].sourceForced)
        #expect(groups[0].staves.allSatisfy { $0.sourceForced })
        #expect(groups[1].isLastSystem)
    }

    // A one-voice tune goes through the joint path and comes out as it always did.
    @Test func oneVoiceGivesGroupsOfOneStaff() {
        let groups = breaker.breakIntoGroups([voiceLine(widths: [90, 90, 90, 90])],
                                             breaks: [nil, nil, nil, nil],
                                             usableWidth: usableWidth)
        #expect(groups.map(\.staves.count) == [1, 1])
        #expect(groups.map(\.columnCount) == [2, 2])
    }

    // The time signature is stamped on every staff of the first system, and no other.
    @Test func meterGoesOnEveryStaffOfTheFirstSystemOnly() {
        let voices = (0..<2).map { _ in
            LineBreaker.VoiceLine(measures: [90, 90, 90, 90].map(sizedMeasure(width:)),
                                  meter: .fraction(num: 4, den: 4))
        }
        let groups = breaker.breakIntoGroups(voices, breaks: [nil, nil, nil, nil],
                                             usableWidth: usableWidth)
        #expect(groups[0].staves.allSatisfy { $0.meter != nil })
        #expect(groups[1].staves.allSatisfy { $0.meter == nil })
    }
}
