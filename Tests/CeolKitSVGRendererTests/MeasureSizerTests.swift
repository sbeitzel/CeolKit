import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

/// Unit note length used throughout these tests: 1/8 (eighth note as the unit).
/// Quarter note = 2 units, whole note = 8 units.
private let unitNoteLength = Fraction(numerator: 1, denominator: 8)

private func note(duration: Fraction, accidental: Alteration? = nil) -> Note {
    Note(
        pitch: Pitch(step: .c, alteration: .natural, octave: 4),
        writtenAccidental: accidental,
        displayedAccidental: accidental,
        duration: duration,
        ties: .none,
        slurs: .none,
        decorations: [],
        chordSymbol: nil,
        annotations: [],
        beam: .single,
        lyric: nil,
        source: dummyRange
    )
}

private func measure(events: [Event]) -> Measure {
    Measure(
        openingBar: nil,
        events: events,
        closingBar: dummyBar,
        endingNumber: nil,
        source: dummyRange
    )
}

// MARK: - Test suite

@Suite struct MeasureSizerTests {

    let sizer: MeasureSizer

    init() throws {
        let metadata = try BravuraMetadata.load()
        sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
    }

    @Test func wholeNoteHasPositiveNaturalWidth() {
        let m = measure(events: [.note(note(duration: Fraction(numerator: 8, denominator: 1)))])
        let sized = sizer.size(m, unitNoteLength: unitNoteLength)
        #expect(sized.naturalWidth > 0)
    }

    @Test func fourQuarterNotesProduceCorrectOffsetCount() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = (0..<4).map { _ in .note(note(duration: quarter)) }
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        #expect(sized.eventOffsets.count == 4)
    }

    @Test func quarterNoteOffsetsAreStrictlyIncreasing() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = (0..<4).map { _ in .note(note(duration: quarter)) }
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        for i in 1..<sized.eventOffsets.count {
            #expect(sized.eventOffsets[i] > sized.eventOffsets[i - 1])
        }
    }

    @Test func firstEventOffsetIsOneNoteheadWidth() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig()
        let noteW    = metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                       ?? config.staffSize * 1.2
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = [.note(note(duration: quarter))]
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)
        #expect(abs(sized.eventOffsets[0] - noteW) < 0.001)
    }

    @Test func quarterColumnNarrowerThanWholeColumn() {
        let quarterDur = Fraction(numerator: 2, denominator: 1)
        let wholeDur   = Fraction(numerator: 8, denominator: 1)

        let quarterMeasure = measure(events: [.note(note(duration: quarterDur))])
        let wholeMeasure   = measure(events: [.note(note(duration: wholeDur))])

        let quarterSized = sizer.size(quarterMeasure, unitNoteLength: unitNoteLength)
        let wholeSized   = sizer.size(wholeMeasure,   unitNoteLength: unitNoteLength)

        // Quarter column width = naturalWidth − bar padding; whole column must be wider.
        let barPad = SVGRenderConfig().staffSize * 0.5
        let quarterCol = quarterSized.naturalWidth - barPad
        let wholeCol   = wholeSized.naturalWidth   - barPad
        #expect(quarterCol < wholeCol)
    }

    @Test func accidentalWidensColumn() {
        let quarter = Fraction(numerator: 2, denominator: 1)
        let plain  = measure(events: [.note(note(duration: quarter))])
        let sharp  = measure(events: [.note(note(duration: quarter, accidental: .sharp))])

        let plainSized = sizer.size(plain, unitNoteLength: unitNoteLength)
        let sharpSized = sizer.size(sharp, unitNoteLength: unitNoteLength)

        #expect(sharpSized.naturalWidth > plainSized.naturalWidth)
    }

    // MARK: - Grace note pairing

    @Test func gracePairedWithNoteProducesTwoOffsets() {
        let gNote = note(duration: Fraction(numerator: 1, denominator: 2))
        let grace = GraceGroup(kind: .appoggiatura, notes: [gNote], source: dummyRange)
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = [.grace(grace), .note(note(duration: quarter))]
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)

        #expect(sized.eventOffsets.count == 2)
        #expect(sized.eventOffsets[1] > sized.eventOffsets[0])
    }

    @Test func graceNoteOffsetEqualsGraceWidthPlusGap() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig()
        let noteW    = metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                       ?? config.staffSize * 1.2
        let graceNoteW     = noteW * 0.6
        let expectedGraceW = graceNoteW * 1.5   // single grace note
        // Single grace note: flag overhang + 0.25 staffSize clearance (see MeasureSizer.graceNoteGap)
        let flagW          = metadata.glyphBBoxes["flag32ndUp"].map { $0.width * config.staffSize * 0.6 }
                             ?? config.staffSize * 0.625
        let flagOverhang   = max(0.0, 1.25 * graceNoteW + flagW - 1.5 * graceNoteW)
        let expectedGap    = flagOverhang + config.staffSize * 0.25
        let expectedNoteOffset = noteW + expectedGraceW + expectedGap

        let gNote = note(duration: Fraction(numerator: 1, denominator: 2))
        let grace = GraceGroup(kind: .appoggiatura, notes: [gNote], source: dummyRange)
        let quarter = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = [.grace(grace), .note(note(duration: quarter))]
        let sized = sizer.size(measure(events: events), unitNoteLength: unitNoteLength)

        #expect(abs(sized.eventOffsets[1] - expectedNoteOffset) < 0.001)
    }

    @Test func graceNoteNotSeparatedFromPrincipalByFullNoteColumn() {
        // A grace+note unit should be narrower than two independent note columns,
        // confirming the grace is attached rather than treated as a separate spacing event.
        let gNote = note(duration: Fraction(numerator: 1, denominator: 2))
        let grace = GraceGroup(kind: .appoggiatura, notes: [gNote], source: dummyRange)
        let quarter = Fraction(numerator: 2, denominator: 1)

        let pairedMeasure = measure(events: [.grace(grace), .note(note(duration: quarter))])
        let twoNoteMeasure = measure(events: [.note(note(duration: quarter)), .note(note(duration: quarter))])

        let pairedSized   = sizer.size(pairedMeasure,   unitNoteLength: unitNoteLength)
        let twoNoteSized  = sizer.size(twoNoteMeasure,  unitNoteLength: unitNoteLength)

        // Grace+note pair is narrower than two independent notes
        // (grace group is smaller than a full note column).
        #expect(pairedSized.naturalWidth < twoNoteSized.naturalWidth)
    }

    // MARK: - Grace group width (issue #39)

    /// The notes of a beamed embellishment share a beam and sit nearly adjacent, so each
    /// note after the first costs only `graceNoteSpacing` notehead widths — not the
    /// full 1.5 that the group's outer padding would suggest.
    @Test func beamedGraceNotesAdvanceByGraceNoteSpacing() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig()
        let metrics  = GraceMetrics(config: config, metadata: metadata)
        let g        = note(duration: Fraction(numerator: 1, denominator: 2))

        let widths = (1...4).map { count in
            metrics.width(Array(repeating: g, count: count))
        }

        // Each additional notehead adds exactly one advance.
        for i in 1..<widths.count {
            #expect(abs((widths[i] - widths[i - 1]) - metrics.advance) < 0.001)
        }
        #expect(abs(metrics.advance - metrics.noteheadWidth * config.graceNoteSpacing) < 0.001)
        // The advance is well under the 1.5 × notehead width charged before issue #39.
        #expect(metrics.advance < metrics.noteheadWidth * 1.5)
    }

    /// Single grace notes were already spaced correctly; issue #39 must not move them.
    @Test func singleGraceGroupWidthIsUnchanged() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig()
        let metrics  = GraceMetrics(config: config, metadata: metadata)
        let g        = note(duration: Fraction(numerator: 1, denominator: 2))

        #expect(abs(metrics.width([g]) - metrics.noteheadWidth * 1.5) < 0.001)
    }

    @Test func graceNoteSpacingConfigNarrowsBeamedGroups() throws {
        let metadata = try BravuraMetadata.load()
        let g        = note(duration: Fraction(numerator: 1, denominator: 2))
        let grace    = GraceGroup(kind: .appoggiatura, notes: [g, g, g], source: dummyRange)
        let quarter  = Fraction(numerator: 2, denominator: 1)
        let events: [Event] = [.grace(grace), .note(note(duration: quarter))]

        let wide  = MeasureSizer(config: SVGRenderConfig(graceNoteSpacing: 1.5), metadata: metadata)
        let tight = MeasureSizer(config: SVGRenderConfig(graceNoteSpacing: 1.05), metadata: metadata)

        let wideSized  = wide.size(measure(events: events),  unitNoteLength: unitNoteLength)
        let tightSized = tight.size(measure(events: events), unitNoteLength: unitNoteLength)

        #expect(tightSized.naturalWidth < wideSized.naturalWidth)
        // The principal note follows the grace group, so it moves left by the same amount.
        #expect(tightSized.eventOffsets[1] < wideSized.eventOffsets[1])
    }

    /// A grace note with an accidental gets a wider step into it: the accidental glyph is
    /// drawn to the left of the notehead and must clear the preceding note's stem.
    @Test func graceNoteWithAccidentalWidensTheStepIntoIt() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig()
        let metrics  = GraceMetrics(config: config, metadata: metadata)
        let accMetrics = AccidentalMetrics(config: config, metadata: metadata)
        let plain    = note(duration: Fraction(numerator: 1, denominator: 2))
        let sharp    = note(duration: Fraction(numerator: 1, denominator: 2), accidental: .sharp)

        let plainOffsets = metrics.noteheadOffsets([plain, plain])
        let sharpOffsets = metrics.noteheadOffsets([plain, sharp])

        #expect(abs((plainOffsets[1] - plainOffsets[0]) - metrics.advance) < 0.001)

        // The accidental must clear the previous note's stem, at the right edge of its notehead.
        let accSpace = accMetrics.offset(for: .sharp, scale: GraceMetrics.scale)
        #expect(abs((sharpOffsets[1] - sharpOffsets[0])
                    - (metrics.noteheadWidth + accSpace)) < 0.001)
        #expect(sharpOffsets[1] - sharpOffsets[0] > metrics.advance)
    }

    /// An accidental on the *first* note of a group hangs left of the notehead, so the
    /// group's leading edge has to grow to hold it.
    @Test func leadingGraceAccidentalWidensTheGroupsLeftEdge() throws {
        let metadata   = try BravuraMetadata.load()
        let config     = SVGRenderConfig()
        let metrics    = GraceMetrics(config: config, metadata: metadata)
        let accMetrics = AccidentalMetrics(config: config, metadata: metadata)
        let plain      = note(duration: Fraction(numerator: 1, denominator: 2))
        let flat       = note(duration: Fraction(numerator: 1, denominator: 2), accidental: .flat)

        let plainOffset = metrics.noteheadOffsets([plain])[0]
        let flatOffset  = metrics.noteheadOffsets([flat])[0]

        #expect(abs(plainOffset - metrics.noteheadWidth * GraceMetrics.edgePad) < 0.001)
        #expect(abs(flatOffset - accMetrics.offset(for: .flat, scale: GraceMetrics.scale)) < 0.001)
        // The accidental starts at the group's left edge, not left of it.
        #expect(flatOffset > plainOffset)
    }

    // MARK: - Accidental placement (issue #44)

    /// Accidentals differ in width by more than 2×, so the space reserved for one must come
    /// from its own glyph rather than a single fixed offset.
    @Test func accidentalReservationTracksGlyphWidth() throws {
        let metadata = try BravuraMetadata.load()
        let metrics  = AccidentalMetrics(config: SVGRenderConfig(), metadata: metadata)

        let natural    = try #require(metrics.width(for: .natural))
        let sharp      = try #require(metrics.width(for: .sharp))
        let flat       = try #require(metrics.width(for: .flat))
        let doubleFlat = try #require(metrics.width(for: .doubleFlat))

        // Ordering follows the Bravura bounding boxes.
        #expect(natural < flat)
        #expect(flat < sharp)
        #expect(sharp < doubleFlat)

        // Every reservation clears its own glyph — that is the bug in #44.
        for alt in [Alteration.natural, .sharp, .flat, .doubleFlat, .doubleSharp] {
            let width = try #require(metrics.width(for: alt))
            #expect(metrics.offset(for: alt) > width)
        }
    }

    /// Microtonal alterations have no glyph in the v0.1 set and draw nothing, so they
    /// must not reserve space either.
    @Test func microtonalAccidentalReservesNoSpace() throws {
        let metadata = try BravuraMetadata.load()
        let metrics  = AccidentalMetrics(config: SVGRenderConfig(), metadata: metadata)
        let quarterSharp = Alteration(numerator: 1, denominator: 2)

        #expect(metrics.width(for: quarterSharp) == nil)
        #expect(metrics.offset(for: quarterSharp) == 0)
        #expect(metrics.reservation(for: quarterSharp) == 0)
    }

    @Test func doubleFlatReservesMoreColumnThanNatural() throws {
        let metadata = try BravuraMetadata.load()
        let sizer    = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
        let quarter  = Fraction(numerator: 2, denominator: 1)

        let natural = measure(events: [.note(note(duration: quarter, accidental: .natural))])
        let dblFlat = measure(events: [.note(note(duration: quarter, accidental: .doubleFlat))])

        let naturalSized = sizer.size(natural, unitNoteLength: unitNoteLength)
        let dblFlatSized = sizer.size(dblFlat, unitNoteLength: unitNoteLength)

        #expect(dblFlatSized.naturalWidth > naturalSized.naturalWidth)
    }
}
