import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

private func sizedMeasure(width: Double, offsets: [Double] = []) -> SizedMeasure {
    let m = Measure(
        openingBar: nil,
        events: [],
        closingBar: dummyBar,
        endingNumber: nil,
        source: dummyRange
    )
    return SizedMeasure(measure: m, naturalWidth: width, eventOffsets: offsets)
}

private func makeSystem(widths: [Double], isLast: Bool, sourceForced: Bool = false) -> System {
    System(
        measures: widths.map { sizedMeasure(width: $0) },
        isLastSystem: isLast,
        sourceForced: sourceForced
    )
}

private let usableWidth: Double = 300

// MARK: - Test suite

@Suite struct JustifierTests {

    let justifier = Justifier()

    // Non-last system: final widths sum to exactly usableWidth.
    @Test func nonLastSystemFillsUsableWidth() {
        let system = makeSystem(widths: [80, 100, 60], isLast: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        let totalFinal = result[0].measures.reduce(0.0) { $0 + $1.finalWidth }
        #expect(abs(totalFinal - usableWidth) < 1e-9)
    }

    // Non-last system: every measure's finalWidth ≥ naturalWidth.
    @Test func nonLastSystemNeverShrinksAMeasure() {
        let system = makeSystem(widths: [80, 100, 60], isLast: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        for (jm, sm) in zip(result[0].measures, system.measures) {
            #expect(jm.finalWidth >= sm.naturalWidth)
        }
    }

    // Last system without justifyLastSystem: finalWidth == naturalWidth for each measure.
    @Test func lastSystemUnchangedWhenNotJustified() {
        let system = makeSystem(widths: [80, 100, 60], isLast: true)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        for (jm, sm) in zip(result[0].measures, system.measures) {
            #expect(abs(jm.finalWidth - sm.naturalWidth) < 1e-9)
        }
    }

    // Last system with justifyLastSystem == true: sum equals usableWidth.
    @Test func lastSystemFilledWhenJustifyLastEnabled() {
        let system = makeSystem(widths: [80, 100, 60], isLast: true)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: true)
        let totalFinal = result[0].measures.reduce(0.0) { $0 + $1.finalWidth }
        #expect(abs(totalFinal - usableWidth) < 1e-9)
    }

    // eventOffsets are rescaled proportionally to finalWidth / naturalWidth.
    @Test func eventOffsetsRescaledProportionally() {
        let sized = sizedMeasure(width: 100, offsets: [0, 25, 50, 75])
        let system = System(measures: [sized], isLastSystem: false, sourceForced: false)
        let result = justifier.justify([system], usableWidth: usableWidth, justifyLastSystem: false)
        let jm = result[0].measures[0]
        let scale = jm.finalWidth / sized.naturalWidth
        let expected = sized.eventOffsets.map { $0 * scale }
        for (got, want) in zip(jm.eventOffsets, expected) {
            #expect(abs(got - want) < 1e-9)
        }
    }

    // isLastSystem and sourceForced flags are preserved through justification.
    @Test func metadataFlagsArePreserved() {
        let systems = [
            makeSystem(widths: [100, 100], isLast: false, sourceForced: true),
            makeSystem(widths: [80], isLast: true, sourceForced: false),
        ]
        let result = justifier.justify(systems, usableWidth: usableWidth, justifyLastSystem: false)
        #expect(result[0].sourceForced == true)
        #expect(result[0].isLastSystem == false)
        #expect(result[1].sourceForced == false)
        #expect(result[1].isLastSystem == true)
    }

    // Empty system list produces empty output.
    @Test func emptyInputProducesEmptyOutput() {
        let result = justifier.justify([], usableWidth: usableWidth, justifyLastSystem: false)
        #expect(result.isEmpty)
    }
}
