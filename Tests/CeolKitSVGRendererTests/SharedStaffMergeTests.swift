import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let config   = SVGRenderConfig()
private let metadata = try! BravuraMetadata.load()
private let sizer    = MeasureSizer(config: config, metadata: metadata)
private let eighth   = Fraction(numerator: 1, denominator: 8)

/// The first bar of every voice of `abc`, in `V:` declaration order.
private func firstBars(_ abc: String) -> [Measure] {
    CeolKitParser().parse(abc, options: .default).score.tunes[0]
        .voices.map { $0.staves[0].measures[0] }
}

private func shared(_ measures: [Measure], padding: Set<Int> = [],
                    unitNoteLength: Fraction = eighth) -> SizedMeasure {
    sizer.size(sharedStaff: measures.enumerated().map { index, measure in
        MeasureSizer.SharedVoice(measure: measure, unitNoteLength: unitNoteLength,
                                 voiceIndex: index, isPadding: padding.contains(index))
    })
}

/// The offsets of one voice's events within a merged measure.
private func offsets(of voice: Int, in merged: SizedMeasure) -> [Double] {
    zip(merged.eventOffsets, merged.eventVoiceIndices).filter { $0.1 == voice }.map(\.0)
}

/// The merged measure's distinct x positions, left to right.  Two events at the same x are
/// one column, which is the whole point of the merge.
private func columns(of merged: SizedMeasure) -> [Double] {
    Array(Set(merged.eventOffsets)).sorted()
}

private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

/// Issue #76: the voices of a `%%score ( … )` group are merged onto one onset grid so they
/// can share a staff.  Everything here is layout — the emitter draws whatever the offsets
/// say, and #77/#78 are what make it *look* like two voices.
@Suite("Shared staff merge")
struct SharedStaffMergeTests {

    // MARK: - Degenerate cases: the merge must vanish

    @Test("Two identical voices lay out exactly as one voice alone")
    func identicalVoicesMatchOneVoice() {
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]CDEFGABc|
            [V:2]CDEFGABc|
            """)
        let merged = shared(bars)
        let alone  = sizer.size(bars[0], unitNoteLength: eighth)

        #expect(isClose(merged.naturalWidth, alone.naturalWidth))
        #expect(columns(of: merged).count == 8)
        for voice in 0...1 {
            #expect(zip(offsets(of: voice, in: merged), alone.eventOffsets).allSatisfy(isClose))
        }
    }

    @Test("A voice the aligner padded contributes no columns at all")
    func paddedVoiceContributesNothing() {
        // The second voice's bar is one the aligner invented, so the staff is the first
        // voice's alone — invisible rest and all, it must not widen a single column.
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]CDEF|
            [V:2]X|
            """)
        let merged = shared(bars, padding: [1])
        let alone  = sizer.size(bars[0], unitNoteLength: eighth)

        #expect(isClose(merged.naturalWidth, alone.naturalWidth))
        #expect(zip(merged.eventOffsets, alone.eventOffsets).allSatisfy(isClose))
        #expect(merged.measure.events.count == alone.measure.events.count)
        #expect(merged.eventVoiceIndices.allSatisfy { $0 == 0 })
    }

    @Test("Every voice padded leaves a bar with no music in it")
    func everyVoicePadded() {
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]X|
            [V:2]X|
            """)
        let merged = shared(bars, padding: [0, 1])
        #expect(merged.eventOffsets.isEmpty)
        #expect(merged.measure.events.isEmpty)
    }

    // MARK: - Onsets

    @Test("Notes that sound together land in one column at one x")
    func simultaneousNotesShareAColumn() {
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]CDEF|
            [V:2]EFGA|
            """)
        let merged = shared(bars)

        #expect(merged.eventOffsets.count == 8)
        #expect(columns(of: merged).count == 4)
        // Emitted voice by voice within each onset, so the pairs are adjacent.
        #expect(merged.eventVoiceIndices == [0, 1, 0, 1, 0, 1, 0, 1])
        for pair in stride(from: 0, to: 8, by: 2) {
            #expect(isClose(merged.eventOffsets[pair], merged.eventOffsets[pair + 1]))
        }
    }

    @Test("Voices in strict alternation interleave, each note at its own onset")
    func alternatingVoicesInterleave() {
        // V:1 sounds on the beat, V:2 off it: onsets 0, ½, 1, 1½ quarter notes.
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]C2E2|
            [V:2]zD2z|
            """)
        let merged = shared(bars)
        let grid = columns(of: merged)

        #expect(grid.count == 4)
        // The upper voice took the first and third columns…
        let upper = offsets(of: 0, in: merged)
        #expect(upper.count == 2)
        #expect(isClose(upper[0], grid[0]))
        #expect(isClose(upper[1], grid[2]))
        // …and the lower voice's note landed between them, on a column of its own.
        let lower = offsets(of: 1, in: merged)
        #expect(lower.count == 3)
        #expect(isClose(lower[0], grid[0]))
        #expect(isClose(lower[1], grid[1]))
        #expect(isClose(lower[2], grid[3]))
    }

    @Test("A long note is spaced by the onsets it sounds across, not by its own length")
    func longNoteSpansTheColumnsUnderIt() {
        // A half note against four eighths: the half note occupies the first of four
        // columns, and the eighths keep an eighth note's spacing under it.
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]C4|
            [V:2]EFGA|
            """)
        let merged = shared(bars)
        let grid = columns(of: merged)

        #expect(grid.count == 4)
        #expect(isClose(offsets(of: 0, in: merged)[0], grid[0]))
        // The four eighth columns are evenly spaced — the long note widened none of them.
        let steps = zip(grid.dropFirst(), grid).map(-)
        #expect(steps.allSatisfy { isClose($0, steps[0]) })
        // And the lower voice alone would have used exactly the same grid.
        let alone = sizer.size(bars[1], unitNoteLength: eighth)
        #expect(zip(grid, alone.eventOffsets).allSatisfy(isClose))
    }

    @Test("Voices with different L: values still meet on the same onsets")
    func differingUnitNoteLengthsAgree() {
        // `C2` at L:1/8 and `C` at L:1/4 are the same quarter note, so the two voices sound
        // together on every beat and the staff gets four columns, not eight.
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]C2D2E2F2|
            [V:2][L:1/4]CDEF|
            """)
        let merged = sizer.size(sharedStaff: [
            MeasureSizer.SharedVoice(measure: bars[0], unitNoteLength: eighth,
                                     voiceIndex: 0, isPadding: false),
            MeasureSizer.SharedVoice(measure: bars[1],
                                     unitNoteLength: Fraction(numerator: 1, denominator: 4),
                                     voiceIndex: 1, isPadding: false)
        ])
        #expect(merged.eventOffsets.count == 8)
        #expect(columns(of: merged).count == 4)
    }

    // MARK: - Grace notes

    @Test("A grace group keeps its principal note adjacent, and its gap unchanged")
    func graceGroupsSurviveTheMerge() throws {
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]{g}A2B2|
            [V:2]C2D2|
            """)
        let merged = shared(bars)
        let alone  = sizer.size(bars[0], unitNoteLength: eighth)

        #expect(!merged.graceEventIndices.isEmpty)
        let graceIndex = try #require(alone.graceEventIndices.min())
        let aloneGap = alone.eventOffsets[graceIndex + 1] - alone.eventOffsets[graceIndex]
        for index in merged.graceEventIndices {
            // Adjacency is what `Justifier.stretchOffsets` reads, so it is the contract.
            #expect(index + 1 < merged.measure.events.count)
            if case .grace = merged.measure.events[index] {} else { Issue.record("not a grace") }
            #expect(merged.eventVoiceIndices[index] == merged.eventVoiceIndices[index + 1])
            // The grace-to-note gap is a fixed measurement, so the merge must not change it.
            #expect(isClose(merged.eventOffsets[index + 1] - merged.eventOffsets[index], aloneGap))
        }
    }

    @Test("Justification preserves the grace gap of a merged measure")
    func justifyingAMergedMeasureKeepsTheGraceGap() {
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]{g}A2B2|
            [V:2]C2D2|
            """)
        let merged = shared(bars)
        let index  = merged.graceEventIndices.min()!
        let gap    = merged.eventOffsets[index + 1] - merged.eventOffsets[index]

        let system = System(measures: [merged], isLastSystem: false, sourceForced: false)
        let justified = Justifier().justify([system], usableWidth: merged.naturalWidth * 2,
                                            justifyLastSystem: true)
        let stretched = justified[0].measures[0]

        #expect(stretched.eventOffsets != merged.eventOffsets)   // it really did stretch
        #expect(isClose(stretched.eventOffsets[index + 1] - stretched.eventOffsets[index], gap))
        // The voices still meet: the second voice's first note stayed under the first
        // voice's, which is what an out-of-order offsets array most easily breaks.
        let upper = zip(stretched.eventOffsets, stretched.eventVoiceIndices)
            .filter { $0.1 == 0 }.map(\.0)
        let lower = zip(stretched.eventOffsets, stretched.eventVoiceIndices)
            .filter { $0.1 == 1 }.map(\.0)
        #expect(isClose(upper[1], lower[0]))   // grace's principal over voice 2's first note
    }

    // MARK: - End to end

    @Test("%%score (1 2) draws one staff; %%score [1 2] still draws two")
    func planDecidesTheStaffCount() throws {
        func staffCount(_ plan: String) throws -> Int {
            let abc = """
                X:1
                L:1/4
                \(plan)
                V:1
                V:2
                K:C
                [V:1]CDEF|
                [V:2]EFGA|
                """
            let score = CeolKitParser().parse(abc, options: .default).score
            var diagnostics: [Diagnostic] = []
            let svgs = try SVGRenderer().render(score, diagnostics: &diagnostics)
            return try SVGGeometry.pages(from: svgs).flatMap(\.systems).count
        }
        #expect(try staffCount("%%score (1 2)") == 1)
        #expect(try staffCount("%%score [1 2]") == 2)
    }

    @Test("Voices on separate staves are sized exactly as the single-voice sizer sizes them")
    func separateStavesAreUntouched() {
        // The driver runs every staff through the shared-staff entry point, so a staff of one
        // voice has to come out of it bit for bit as it did before the merge existed.
        let bars = firstBars("""
            X:1
            L:1/8
            K:C
            V:1
            V:2
            [V:1]{g}CDEFG2A2|
            [V:2]EFGAB2c2|
            """)
        for bar in bars {
            let viaShared = shared([bar])
            let alone     = sizer.size(bar, unitNoteLength: eighth)
            #expect(isClose(viaShared.naturalWidth, alone.naturalWidth))
            #expect(zip(viaShared.eventOffsets, alone.eventOffsets).allSatisfy(isClose))
            #expect(viaShared.graceEventIndices == alone.graceEventIndices)
            #expect(viaShared.eventVoiceIndices == alone.eventVoiceIndices)
        }
    }
}
