import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

private func measure(line: Int) -> Measure {
    Measure(openingBar: nil, events: [], closingBar: dummyBar, endingNumber: nil,
            source: SourceRange(file: nil, byteOffset: 0, length: 0, line: line, column: 0),
            unitNoteLength: Fraction(numerator: 1, denominator: 8))
}

/// A voice whose staves are given as measure counts — one stave per source line.
private func voice(_ id: String, staves: [Int]) -> Voice {
    Voice(
        id: .named(id),
        properties: VoiceProperties(
            clef:            ClefSpec(clef: .treble, octaveShift: 0),
            transposition:   .none,
            staffProperties: StaffProperties(staffLines: 5),
            name:            nil,
            subname:         nil,
            stemDirection:   .auto,
            middleNote:      nil
        ),
        staves: staves.enumerated().map { index, count in
            Staff(measures: (0..<count).map { _ in measure(line: index + 1) }, overlays: [])
        },
        directives: [],
        source: dummyRange
    )
}

private func isInvisibleFullMeasureRest(_ m: Measure) -> Bool {
    guard m.events.count == 1, case .rest(let rest) = m.events[0] else { return false }
    return rest.kind == .fullMeasureInvisible
}

// MARK: - Tests

@Suite struct VoiceAlignerTests {

    // Voices that already agree pass through untouched and silently.
    @Test func agreeingVoicesPassThrough() {
        var diagnostics: [Diagnostic] = []
        let staves = VoiceAligner.align([voice("1", staves: [4, 4]), voice("2", staves: [4, 4])],
                                        into: &diagnostics)
        #expect(staves.map(\.measureCount) == [4, 4])
        #expect(staves.allSatisfy { $0.measures.count == 2 })
        #expect(diagnostics.isEmpty)
    }

    // A single voice is never warned about, however ragged its staves are.
    @Test func singleVoiceIsNeverWarnedAbout() {
        var diagnostics: [Diagnostic] = []
        let staves = VoiceAligner.align([voice("1", staves: [4, 2, 7])], into: &diagnostics)
        #expect(staves.map(\.measureCount) == [4, 2, 7])
        #expect(diagnostics.isEmpty)
    }

    // The short voice is padded up to the long one, with invisible full-measure rests.
    @Test func shortVoiceIsPaddedWithInvisibleRests() {
        var diagnostics: [Diagnostic] = []
        let staves = VoiceAligner.align([voice("1", staves: [4]), voice("2", staves: [2])],
                                        into: &diagnostics)
        #expect(staves[0].measureCount == 4)
        #expect(staves[0].measures[1].count == 4)
        // The two real measures are kept; only the tail is filler.
        #expect(!isInvisibleFullMeasureRest(staves[0].measures[1][1]))
        #expect(isInvisibleFullMeasureRest(staves[0].measures[1][2]))
        #expect(isInvisibleFullMeasureRest(staves[0].measures[1][3]))
    }

    // Padding is per source line, so a short line does not pull the next line's music up
    // into it — the voices stay line for line, which is how they were written.
    @Test func paddingIsPerSourceLine() {
        var diagnostics: [Diagnostic] = []
        let staves = VoiceAligner.align([voice("1", staves: [4, 4]), voice("2", staves: [2, 4])],
                                        into: &diagnostics)
        #expect(staves.map(\.measureCount) == [4, 4])
        // Line 2 of the short voice is its own music, not line 1's overflow.
        #expect(staves[1].measures[1].allSatisfy { !isInvisibleFullMeasureRest($0) })
    }

    // A voice with fewer source lines gains whole padded lines rather than being dropped.
    @Test func voiceWithFewerStavesGainsWholeLines() {
        var diagnostics: [Diagnostic] = []
        let staves = VoiceAligner.align([voice("1", staves: [4, 4]), voice("2", staves: [4])],
                                        into: &diagnostics)
        #expect(staves.count == 2)
        #expect(staves[1].measures[1].count == 4)
        #expect(staves[1].measures[1].allSatisfy(isInvisibleFullMeasureRest))
    }

    // The warning names both voices and points at the bar where they part.
    @Test func mismatchWarningNamesTheVoicesAndTheBar() {
        var diagnostics: [Diagnostic] = []
        _ = VoiceAligner.align([voice("Melody", staves: [4]), voice("Alternate", staves: [2])],
                               into: &diagnostics)
        #expect(diagnostics.count == 1)
        let warning = diagnostics[0]
        #expect(warning.code == .voiceLengthMismatch)
        #expect(warning.severity == .warning)
        #expect(warning.message.contains("Melody"))
        #expect(warning.message.contains("Alternate"))
        // Measures 1 and 2 are shared; measure 3 is the first the short voice lacks.
        #expect(warning.hint?.contains("measure 3") == true)
    }

    // Bar numbers in the hint run across the whole tune, not within a line.
    @Test func mismatchBarNumberIsCountedFromTheStartOfTheTune() {
        var diagnostics: [Diagnostic] = []
        _ = VoiceAligner.align([voice("1", staves: [4, 4]), voice("2", staves: [4, 1])],
                               into: &diagnostics)
        #expect(diagnostics.count == 1)
        // Four bars in line 1, then one in line 2 — bar 6 is where they part.
        #expect(diagnostics[0].hint?.contains("measure 6") == true)
    }

    // One warning per line that disagrees, not one per padded measure.
    @Test func oneWarningPerDisagreeingLine() {
        var diagnostics: [Diagnostic] = []
        _ = VoiceAligner.align([voice("1", staves: [4, 4, 4]), voice("2", staves: [1, 4, 1])],
                               into: &diagnostics)
        #expect(diagnostics.count == 2)
    }

    @Test func noVoicesProducesNoStaves() {
        var diagnostics: [Diagnostic] = []
        #expect(VoiceAligner.align([], into: &diagnostics).isEmpty)
        #expect(diagnostics.isEmpty)
    }
}
