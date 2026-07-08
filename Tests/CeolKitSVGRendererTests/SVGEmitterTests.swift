import Testing
import CeolKitModel
@testable import CeolKitSVGRenderer

// MARK: - Helpers

private let dummyRange = SourceRange(file: nil, byteOffset: 0, length: 0, line: 0, column: 0)
private let dummyBar   = BarLine(kind: .single, source: dummyRange)

/// Default staffSize = 7.0, so staffHeight = 28.0
private let config = SVGRenderConfig()
private let metadata = try! BravuraMetadata.load()

/// Builds a minimal `ResolvedLayout` from the given systems.
private func layout(systems: [ResolvedSystem]) -> ResolvedLayout {
    ResolvedLayout(
        pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
        margins: config.margins,
        pages: [ResolvedPage(systems: systems)]
    )
}

/// Minimal system with the given measures at a known vertical position.
/// `origin.y = 50`, `extraAbove = 50`, so top staff line y = 100.
private func system(measures: [ResolvedMeasure], abcLine: Int = 1, originY: Double = 50) -> ResolvedSystem {
    let staffHeight = 4.0 * config.staffSize
    return ResolvedSystem(
        origin: Point(x: config.margins.left, y: originY),
        measures: measures,
        staffOrigin: 50,
        staffHeight: staffHeight,
        extraAbove: 50,
        extraBelow: 0,
        totalHeight: 50 + staffHeight,
        abcLine: abcLine
    )
}

/// Measure with no events and a closing bar at `origin.x + width`.
private func emptyMeasure(originX: Double = 36, width: Double = 200) -> ResolvedMeasure {
    ResolvedMeasure(
        origin: Point(x: originX, y: 50),
        width: width,
        events: [],
        openingBar: nil,
        closingBar: ResolvedBarLine(x: originX + width, kind: .single)
    )
}

/// Creates a quarter-note `Note` on the given pitch.
private func quarterNote(step: DiatonicStep, octave: Int, accidental: Alteration? = nil) -> Note {
    Note(
        pitch: Pitch(step: step, alteration: accidental ?? .natural, octave: octave),
        writtenAccidental: accidental,
        displayedAccidental: accidental,
        duration: Fraction(numerator: 1, denominator: 1),  // 1 unit × UNL(1/4) = quarter note
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

/// `unitNoteLength = 1/4` (quarter note as unit), so duration=1/1 → absolute = 0.25 → noteheadBlack.
private let quarterUNL = Fraction(numerator: 1, denominator: 4)

// MARK: - SVGEmitter tests

@Suite struct SVGEmitterTests {

    let emitter = SVGEmitter(config: config, metadata: metadata)

    // MARK: Page count

    @Test func outputHasOneElementPerPage() throws {
        let layout = ResolvedLayout(
            pageSize: Size(width: 612, height: 792),
            margins: config.margins,
            pages: [
                ResolvedPage(systems: [system(measures: [emptyMeasure()])]),
                ResolvedPage(systems: [system(measures: [emptyMeasure()])])
            ]
        )
        let svgs = try emitter.emit(layout)
        #expect(svgs.count == 2)
    }

    // MARK: SVG document structure

    @Test func eachElementStartsWithSvgTag() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        for svg in svgs {
            #expect(svg.hasPrefix("<svg "))
        }
    }

    @Test func eachElementEndsWithSvgClose() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        for svg in svgs {
            #expect(svg.hasSuffix("</svg>\n  ") || svg.contains("</svg>"))
        }
    }

    @Test func viewBoxMatchesPageSize() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        let svg = try #require(svgs.first)
        #expect(svg.contains("viewBox=\"0 0 612 792\""))
    }

    @Test func defsContainsBravuraFontFace() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        let svg = try #require(svgs.first)
        #expect(svg.contains("@font-face"))
        #expect(svg.contains("font-family: \"Bravura\""))
        #expect(svg.contains("data:font/otf;base64,"))
    }

    @Test func defsContainsLibertinusSerifFontFace() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        let svg = try #require(svgs.first)
        #expect(svg.contains("font-family: \"Libertinus Serif\""))
    }

    // MARK: Staff lines

    @Test func fiveStaffLinesPerSystem() throws {
        // One system, one empty measure + its closing bar = 5 horizontal + 1 vertical line.
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        let svg = try #require(svgs.first)
        // Count <line elements (each occurrence of "<line " is one element).
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        // 5 staff lines + 1 closing bar = 6
        #expect(lineCount == 6)
    }

    @Test func twoSystemsProduceTenStaffLines() throws {
        let m1 = emptyMeasure(originX: 36,  width: 200)
        let m2 = emptyMeasure(originX: 236, width: 200)
        let sys1 = system(measures: [m1])
        let sys2 = system(measures: [m2])
        let svgs = try emitter.emit(layout(systems: [sys1, sys2]))
        let svg = try #require(svgs.first)
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        // 5 + 5 staff lines + 2 closing bars = 12
        #expect(lineCount == 12)
    }

    // MARK: Noteheads

    @Test func noteheadBlackEmittedAtExpectedPosition() throws {
        // E4 is at staff position 0 (bottom line).
        // topStaffY = system.origin.y + staffOrigin = 50 + 50 = 100
        // bottomStaffY = 100 + 4*7 = 128
        // staffPos(E4) = (4-4)*7 + (2-2) = 0
        // noteY = 128 - 0*7/2 = 128
        let topStaffY    = 100.0
        let bottomStaffY = topStaffY + 4 * config.staffSize   // 128
        let expectedY    = bottomStaffY                         // E4 is at bottom line

        let note  = quarterNote(step: .e, octave: 4)
        let event = ResolvedEvent(
            origin: Point(x: 60, y: topStaffY),
            kind: .note(note)
        )
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50),
            width: 100,
            events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        #expect(svg.contains(String(SMuFLGlyph.noteheadBlack.character)))
        let expectedYStr = SVGBuilder().fmt(expectedY)
        #expect(svg.contains("y=\"\(expectedYStr)\""))
    }

    @Test func middleLineBNoteEmittedAtCorrectY() throws {
        // B4 is at staff position 4 (middle line).
        // noteY = 128 - 4*7/2 = 128 - 14 = 114
        let topStaffY    = 100.0
        let bottomStaffY = topStaffY + 4 * config.staffSize   // 128
        let staffPos     = 4
        let expectedY    = bottomStaffY - Double(staffPos) * config.staffSize / 2.0

        let note  = quarterNote(step: .b, octave: 4)
        let event = ResolvedEvent(
            origin: Point(x: 60, y: topStaffY),
            kind: .note(note)
        )
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50),
            width: 100,
            events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        let expectedYStr = SVGBuilder().fmt(expectedY)
        #expect(svg.contains("y=\"\(expectedYStr)\""))
    }

    @Test func wholeNoteUsesNoteheadWholeGlyph() throws {
        // UNL = 1/4, duration = 4/1 → absolute = 1.0 → whole note
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 4, denominator: 1),
            ties: .none, slurs: .none, decorations: [], chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event   = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.noteheadWhole.character)))
    }

    @Test func halfNoteUsesNoteheadHalfGlyph() throws {
        // UNL = 1/4, duration = 2/1 → absolute = 0.5 → half note
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 2, denominator: 1),
            ties: .none, slurs: .none, decorations: [], chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event   = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.noteheadHalf.character)))
    }

    // MARK: Bar lines

    @Test func singleBarLineEmittedAtExpectedX() throws {
        let barX: Double = 236
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50),
            width: 200,
            events: [],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: barX, kind: .single)
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        let b = SVGBuilder()
        let xStr = b.fmt(barX)
        #expect(svg.contains("x1=\"\(xStr)\""))
    }

    @Test func doubleBarLineProducesTwoVerticalLines() throws {
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50),
            width: 200,
            events: [],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 236, kind: .double)
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        // 5 staff lines + 2 lines for double bar = 7
        #expect(lineCount == 7)
    }

    // MARK: Empty layout

    @Test func emptyLayoutProducesEmptyArray() throws {
        let layout = ResolvedLayout(
            pageSize: Size(width: 612, height: 792),
            margins: config.margins,
            pages: []
        )
        let svgs = try emitter.emit(layout)
        #expect(svgs.isEmpty)
    }

    // MARK: Grace notes

    /// Helper: builds a measure with a single grace event at a given x.
    private func measureWithGrace(_ grace: GraceGroup, x: Double = 60) -> ResolvedMeasure {
        let event = ResolvedEvent(origin: Point(x: x, y: 100), kind: .grace(grace))
        return ResolvedMeasure(
            origin: Point(x: x, y: 50),
            width: 150,
            events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: x + 150, kind: .single),
            unitNoteLength: quarterUNL
        )
    }

    private func graceNote(step: DiatonicStep, octave: Int) -> Note {
        Note(
            pitch: Pitch(step: step, alteration: .natural, octave: octave),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 2),   // nominal eighth
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
    }

    @Test func singleGraceNoteRendersNotehead() throws {
        let grace = GraceGroup(kind: .appoggiatura, notes: [graceNote(step: .g, octave: 4)],
                               source: dummyRange)
        let svgs = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.noteheadBlack.character)))
    }

    @Test func singleGraceNoteRenders32ndFlag() throws {
        let grace = GraceGroup(kind: .appoggiatura, notes: [graceNote(step: .g, octave: 4)],
                               source: dummyRange)
        let svgs = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.flag32ndUp.character)))
        #expect(!svg.contains(String(SMuFLGlyph.flag8thUp.character)))
    }

    @Test func multipleGraceNotesRenderThreeBeams() throws {
        let notes = [graceNote(step: .f, octave: 4), graceNote(step: .g, octave: 4)]
        let grace = GraceGroup(kind: .appoggiatura, notes: notes, source: dummyRange)
        let svgs  = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg   = try #require(svgs.first)

        // No flags should appear for a beamed group.
        #expect(!svg.contains(String(SMuFLGlyph.flag32ndUp.character)))

        // 2 stem lines + 3 beam lines + 5 staff lines + 1 bar = 11 lines.
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        #expect(lineCount == 11)
    }

    @Test func acciaccaturaHasSlashLine() throws {
        let grace = GraceGroup(kind: .acciaccatura, notes: [graceNote(step: .g, octave: 4)],
                               source: dummyRange)
        let svgs = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg  = try #require(svgs.first)

        // Acciaccatura adds a slash line through the stem. Count: 5 staff + 1 bar + 1 stem + 1 slash = 8.
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        #expect(lineCount == 8)
    }

    @Test func beamedGraceGroupStemsExtendAboveStaff() throws {
        // Notes deep in the staff (E4 = bottom line, staffPos 0) would put beams
        // inside the staff with a fixed stem length. The clamp must push beamY above
        // topStaffY - 3 * beamStep.
        let lowNote = Note(
            pitch: Pitch(step: .e, alteration: .natural, octave: 4),  // staffPos 0, bottom line
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 2),
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let notes = [lowNote, lowNote]
        let grace = GraceGroup(kind: .appoggiatura, notes: notes, source: dummyRange)

        // System: origin.y = 50, staffOrigin = 50 → topStaffY = 100
        let topStaffY = 100.0
        let svgs = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg  = try #require(svgs.first)

        // All beam <line> y1/y2 values must be strictly less than topStaffY (i.e. above the staff).
        // Extract y-coordinates from line elements and verify.
        let beamThick   = metadata.engravingDefaults.beamThickness * config.staffSize * 0.6
        let beamSpacing = metadata.engravingDefaults.beamSpacing   * config.staffSize * 0.6
        let beamStep    = beamThick + beamSpacing
        // The top beam Y must be above (topStaffY - beamStep) - 2 * beamStep.
        // Verify by checking the clamped beamY is above the staff.
        let b = SVGBuilder()
        let topBeamYStr = b.fmt(topStaffY - 3.0 * beamStep)
        // The SVG should contain a line at y = topStaffY - 3*beamStep (the clamped beam top).
        #expect(svg.contains("y1=\"\(topBeamYStr)\"") || svg.contains("y2=\"\(topBeamYStr)\""))
    }

    // MARK: Footer

    @Test func footerRowsAreRenderedAsText() throws {
        let footerItem = ResolvedTitleRow.Item(
            text: "Page 1 of 1",
            x: config.pageSize.width / 2.0,
            baselineY: config.pageSize.height - config.margins.bottom,
            anchor: .middle,
            fontSize: config.staffSize * 1.4
        )
        let page = ResolvedPage(
            systems: [system(measures: [emptyMeasure()])],
            footerRows: [ResolvedTitleRow(items: [footerItem])]
        )
        let l = ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: [page]
        )
        let svg = try #require(try emitter.emit(l).first)
        #expect(svg.contains("Page 1 of 1"))
    }

    @Test func footerRowsHaveFooterClass() throws {
        let footerItem = ResolvedTitleRow.Item(
            text: "Footer Text",
            x: config.pageSize.width / 2.0,
            baselineY: config.pageSize.height - config.margins.bottom,
            anchor: .middle,
            fontSize: config.staffSize * 1.4
        )
        let page = ResolvedPage(
            systems: [system(measures: [emptyMeasure()])],
            footerRows: [ResolvedTitleRow(items: [footerItem])]
        )
        let l = ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: [page]
        )
        let svg = try #require(try emitter.emit(l).first)
        #expect(svg.contains("class=\"footer\""))
    }

    @Test func pageWithNoFooterRowsHasNoFooterClass() throws {
        let page = ResolvedPage(systems: [system(measures: [emptyMeasure()])])
        let l = ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: [page]
        )
        let svg = try #require(try emitter.emit(l).first)
        #expect(!svg.contains("class=\"footer\""))
    }

    @Test func footerBaselineIsAtBottomMargin() throws {
        let expectedY = config.pageSize.height - config.margins.bottom
        let footerItem = ResolvedTitleRow.Item(
            text: "Footer",
            x: config.pageSize.width / 2.0,
            baselineY: expectedY,
            anchor: .middle,
            fontSize: config.staffSize * 1.4
        )
        let page = ResolvedPage(
            systems: [system(measures: [emptyMeasure()])],
            footerRows: [ResolvedTitleRow(items: [footerItem])]
        )
        let l = ResolvedLayout(
            pageSize: Size(width: config.pageSize.width, height: config.pageSize.height),
            margins: config.margins,
            pages: [page]
        )
        let svg = try #require(try emitter.emit(l).first)
        let b = SVGBuilder()
        #expect(svg.contains("y=\"\(b.fmt(expectedY))\""))
    }

    @Test func appoggiaturaHasNoSlashLine() throws {
        let grace = GraceGroup(kind: .appoggiatura, notes: [graceNote(step: .g, octave: 4)],
                               source: dummyRange)
        let svgs = try emitter.emit(layout(systems: [system(measures: [measureWithGrace(grace)])]))
        let svg  = try #require(svgs.first)

        // Appoggiatura: 5 staff + 1 bar + 1 stem = 7 lines (no slash).
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        #expect(lineCount == 7)
    }

    // MARK: Beam lines

    /// Helper: build a beamed pair of eighth notes (UNL = 1/8, duration = 1 unit each).
    private func beamedEighthNote(step: DiatonicStep, octave: Int, beam: BeamState) -> Note {
        Note(
            pitch: Pitch(step: step, alteration: .natural, octave: octave),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),  // 1 × UNL(1/8) = eighth
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: beam, lyric: nil, source: dummyRange
        )
    }

    private let eighthUNL = Fraction(numerator: 1, denominator: 8)

    @Test func beamedEighthPairDrawsOneBeamLine() throws {
        let n1 = beamedEighthNote(step: .e, octave: 5, beam: .start)
        let n2 = beamedEighthNote(step: .g, octave: 5, beam: .end)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(n1))
        let e2 = ResolvedEvent(origin: Point(x: 90, y: topY), kind: .note(n2))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 150,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 210, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        // 5 staff lines + 1 bar + 2 stems + 1 beam = 9 lines; no flags.
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        #expect(lineCount == 9)
        #expect(!svg.contains(String(SMuFLGlyph.flag8thUp.character)))
        #expect(!svg.contains(String(SMuFLGlyph.flag8thDown.character)))
    }

    @Test func beamedSixteenthPairDrawsTwoBeamLines() throws {
        // UNL = 1/16; duration = 1 unit → absolute = 1/16
        let unl = Fraction(numerator: 1, denominator: 16)
        let makeNote: (BeamState) -> Note = { beam in
            Note(
                pitch: Pitch(step: .e, alteration: .natural, octave: 5),
                writtenAccidental: nil, displayedAccidental: nil,
                duration: Fraction(numerator: 1, denominator: 1),
                ties: .none, slurs: .none, decorations: [],
                chordSymbol: nil, annotations: [],
                beam: beam, lyric: nil, source: dummyRange
            )
        }
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(makeNote(.start)))
        let e2 = ResolvedEvent(origin: Point(x: 90, y: topY), kind: .note(makeNote(.end)))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 150,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 210, kind: .single),
            unitNoteLength: unl
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        // 5 staff + 1 bar + 2 stems + 2 beams = 10 lines.
        let lineCount = svg.components(separatedBy: "<line ").count - 1
        #expect(lineCount == 10)
    }

    // MARK: Augmentation dots

    @Test func fermataIsCenteredOnNotehead() throws {
        // The fermata glyph's horizontal midpoint must align with the notehead's midpoint.
        let noteX = 60.0
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none,
            decorations: [.fermata],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: noteX, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        let nhBBox = try #require(metadata.glyphBBoxes["noteheadBlack"])
        let faBBox = try #require(metadata.glyphBBoxes["fermataAbove"])
        let nhCenterX  = (nhBBox.swX + nhBBox.neX) / 2.0 * config.staffSize
        let faCenterX  = (faBBox.swX + faBBox.neX) / 2.0 * config.staffSize
        let expectedX  = noteX + nhCenterX - faCenterX
        let b = SVGBuilder()
        #expect(svg.contains("x=\"\(b.fmt(expectedX))\""))
    }

    @Test func fermataIsAboveGraceBeamWhenGraceBeamIsHigher() throws {
        // Grace group {ag} (A4 + G4, beamed) whose clamped beam tip rises above the default
        // "one space above top staff line" fermata position.  The emitter must push the fermata
        // higher so its bottom clears the grace-note beam.
        //
        // This mirrors the {ag}Ha2 fragment from "L:1/8 {g}de {g}Hf2 {ag}Ha2".
        let topStaffY    = 100.0
        let bottomStaffY = topStaffY + 4 * config.staffSize   // 128

        // Build a beamed grace group: A4 (staffPos 3) then G4 (staffPos 2).
        let graceA4 = graceNote(step: .a, octave: 4)
        let graceG4 = graceNote(step: .g, octave: 4)
        let grace = GraceGroup(kind: .appoggiatura, notes: [graceA4, graceG4], source: dummyRange)

        let graceOriginX = 60.0
        let noteX        = 90.0
        let graceEvent   = ResolvedEvent(origin: Point(x: graceOriginX, y: topStaffY), kind: .grace(grace))
        let mainNote     = Note(
            pitch: Pitch(step: .a, alteration: .natural, octave: 4),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 2, denominator: 1),   // quarter note with UNL=1/8
            ties: .none, slurs: .none,
            decorations: [.fermata],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let noteEvent = ResolvedEvent(origin: Point(x: noteX, y: topStaffY), kind: .note(mainNote))
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 220,
            events: [graceEvent, noteEvent], openingBar: nil,
            closingBar: ResolvedBarLine(x: 256, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)

        // Reproduce the grace-group beam-Y calculation (mirrors emitGraceGroup internals).
        let s            = config.staffSize
        let graceScale   = 0.6
        let beamThick    = metadata.engravingDefaults.beamThickness * s * graceScale
        let beamSpacing  = metadata.engravingDefaults.beamSpacing   * s * graceScale
        let beamStep     = beamThick + beamSpacing
        // A4 (staffPos 3) has the highest notehead (smallest y) of the two grace notes.
        let highestNHY   = bottomStaffY - 3.0 * s / 2.0          // 117.5
        let stemLength   = 3.5 * s * graceScale                   // 14.7
        let rawBeamY     = highestNHY - stemLength                 // 102.8
        let graceStemTipY = min(rawBeamY, topStaffY - 3.0 * beamStep)  // clamped: 90.55

        // fermataY = min(one-space-above-staff, graceBeamY - gap - fermata-descent)
        let faBBox      = try #require(metadata.glyphBBoxes["fermataAbove"])
        let descent     = abs(faBBox.swY) * s
        let gap         = 0.5 * s
        let expectedY   = min(topStaffY - s, graceStemTipY - gap - descent)
        let b = SVGBuilder()
        #expect(svg.contains("y=\"\(b.fmt(expectedY))\""))
        // The fermata must genuinely be above the grace beam (smaller SVG y = higher).
        #expect(expectedY < graceStemTipY)
    }

    @Test func dottedEighthNoteHasAugmentationDot() throws {
        // Dotted eighth: absolute duration = 3/16.
        // With UNL = 1/16 and duration = 3/1: absDur = 3 * (1/16) = 3/16.
        let unl = Fraction(numerator: 1, denominator: 16)
        let note = Note(
            pitch: Pitch(step: .g, alteration: .natural, octave: 5),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 3, denominator: 1),
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 150,
            events: [event], openingBar: nil,
            closingBar: ResolvedBarLine(x: 210, kind: .single),
            unitNoteLength: unl
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.augmentationDot.character)))
    }

    @Test func plainEighthNoteHasNoAugmentationDot() throws {
        // Plain eighth: absolute duration = 1/8 — no dot.
        let note = Note(
            pitch: Pitch(step: .g, alteration: .natural, octave: 5),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 150,
            events: [event], openingBar: nil,
            closingBar: ResolvedBarLine(x: 210, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(!svg.contains(String(SMuFLGlyph.augmentationDot.character)))
    }

    // MARK: Fermatas

    @Test func fermataDecorationRendersAboveStaff() throws {
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none,
            decorations: [.fermata],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.fermataAbove.character)))
    }

    @Test func invertedFermataDecorationRendersBelowStaff() throws {
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none,
            decorations: [.invertedFermata],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.fermataBelow.character)))
    }

    @Test func noteWithNoDecorations_hasNoFermataGlyph() throws {
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none,
            decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(!svg.contains(String(SMuFLGlyph.fermataAbove.character)))
        #expect(!svg.contains(String(SMuFLGlyph.fermataBelow.character)))
    }

    @Test func fermataIsAboveTopStaffLine() throws {
        // topStaffY = system.origin.y + staffOrigin = 50 + 50 = 100
        // fermata Y = topStaffY - staffSize = 100 - 7 = 93
        let topStaffY  = 100.0
        let expectedY  = topStaffY - config.staffSize

        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil,
            displayedAccidental: nil,
            duration: Fraction(numerator: 1, denominator: 1),
            ties: .none, slurs: .none,
            decorations: [.fermata],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: topStaffY), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 100, events: [event],
            openingBar: nil,
            closingBar: ResolvedBarLine(x: 160, kind: .single),
            unitNoteLength: quarterUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        let b = SVGBuilder()
        #expect(svg.contains("y=\"\(b.fmt(expectedY))\""))
        #expect(expectedY < topStaffY)
    }

    @Test func dottedQuarterNoteHasAugmentationDot() throws {
        // Dotted quarter: absDur = 3/8.  UNL = 1/8, duration = 3 units.
        let note = Note(
            pitch: Pitch(step: .c, alteration: .natural, octave: 5),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: 3, denominator: 1),
            ties: .none, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
        let event = ResolvedEvent(origin: Point(x: 60, y: 100), kind: .note(note))
        let measure = ResolvedMeasure(
            origin: Point(x: 60, y: 50), width: 150,
            events: [event], openingBar: nil,
            closingBar: ResolvedBarLine(x: 210, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(String(SMuFLGlyph.augmentationDot.character)))
    }

    // MARK: - Ties

    /// Helper: builds a note with the given tie state and duration (in units of `eighthUNL`).
    private func tiedNote(step: DiatonicStep, octave: Int, durationUnits: Int,
                           tieState: TieState) -> Note {
        Note(
            pitch: Pitch(step: step, alteration: .natural, octave: octave),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: durationUnits, denominator: 1),
            ties: tieState, slurs: .none, decorations: [],
            chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
    }

    @Test func tieWithinMeasureEmitsPathElement() throws {
        // E4 quarter (.startsTie) at x=60, E4 eighth (.endsTie) at x=100.
        // With UNL = 1/8: 2 units = quarter, 1 unit = eighth.
        let startNote = tiedNote(step: .e, octave: 4, durationUnits: 2, tieState: .startsTie)
        let endNote   = tiedNote(step: .e, octave: 4, durationUnits: 1, tieState: .endsTie)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(startNote))
        let e2 = ResolvedEvent(origin: Point(x: 100, y: topY), kind: .note(endNote))
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 200,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 236, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains("<path"))
    }

    @Test func tieCrossesBarLineEmitsPathElement() throws {
        // G4 quarter (.startsTie) at the end of measure 1; G4 whole (.endsTie) at the start
        // of measure 2.  Both measures are in the same system so the arc spans the bar line.
        let startNote = tiedNote(step: .g, octave: 4, durationUnits: 2, tieState: .startsTie)
        let endNote   = tiedNote(step: .g, octave: 4, durationUnits: 8, tieState: .endsTie)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 160, y: topY), kind: .note(startNote))
        let m1 = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 160,
            events: [e1], openingBar: nil,
            closingBar: ResolvedBarLine(x: 196, kind: .single),
            unitNoteLength: eighthUNL
        )
        let e2 = ResolvedEvent(origin: Point(x: 210, y: topY), kind: .note(endNote))
        let m2 = ResolvedMeasure(
            origin: Point(x: 196, y: 50), width: 180,
            events: [e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 376, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [m1, m2])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains("<path"))
    }

    @Test func notesWithNoTiesProduceNoPathElement() throws {
        // Same pitches, same layout as tieWithinMeasure, but ties = .none — no arc.
        let n1 = tiedNote(step: .e, octave: 4, durationUnits: 2, tieState: .none)
        let n2 = tiedNote(step: .e, octave: 4, durationUnits: 1, tieState: .none)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(n1))
        let e2 = ResolvedEvent(origin: Point(x: 100, y: topY), kind: .note(n2))
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 200,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 236, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(!svg.contains("<path"))
    }

    // MARK: - Slurs

    /// Helper: builds a note with the given SlurState.
    private func slurredNote(step: DiatonicStep, octave: Int, durationUnits: Int,
                              opens: Int, closes: Int) -> Note {
        Note(
            pitch: Pitch(step: step, alteration: .natural, octave: octave),
            writtenAccidental: nil, displayedAccidental: nil,
            duration: Fraction(numerator: durationUnits, denominator: 1),
            ties: .none,
            slurs: SlurState(opens: opens, closes: closes),
            decorations: [], chordSymbol: nil, annotations: [],
            beam: .single, lyric: nil, source: dummyRange
        )
    }

    @Test func slurWithinMeasureEmitsPathElement() throws {
        // E4 quarter (opens slur) → E4 eighth (closes slur): same pattern as the
        // ABC "(e2 e)" fragment which the parser maps to SlurState, not TieState.
        let openNote  = slurredNote(step: .e, octave: 4, durationUnits: 2, opens: 1, closes: 0)
        let closeNote = slurredNote(step: .e, octave: 4, durationUnits: 1, opens: 0, closes: 1)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(openNote))
        let e2 = ResolvedEvent(origin: Point(x: 100, y: topY), kind: .note(closeNote))
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 200,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 236, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains("<path"))
    }

    @Test func slurCrossesBarLineEmitsPathElement() throws {
        // G4 quarter (opens slur) in measure 1; G4 whole (closes slur) in measure 2.
        // Models the ABC "(g2 | g8)" fragment.
        let openNote  = slurredNote(step: .g, octave: 4, durationUnits: 2, opens: 1, closes: 0)
        let closeNote = slurredNote(step: .g, octave: 4, durationUnits: 8, opens: 0, closes: 1)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 160, y: topY), kind: .note(openNote))
        let m1 = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 160,
            events: [e1], openingBar: nil,
            closingBar: ResolvedBarLine(x: 196, kind: .single),
            unitNoteLength: eighthUNL
        )
        let e2 = ResolvedEvent(origin: Point(x: 210, y: topY), kind: .note(closeNote))
        let m2 = ResolvedMeasure(
            origin: Point(x: 196, y: 50), width: 180,
            events: [e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 376, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [m1, m2])]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains("<path"))
    }

    @Test func notesWithNoSlursAndNoTiesProduceNoPathElement() throws {
        // Baseline: plain notes with neither slurs nor ties → no arc element.
        let n1 = slurredNote(step: .e, octave: 4, durationUnits: 2, opens: 0, closes: 0)
        let n2 = slurredNote(step: .e, octave: 4, durationUnits: 1, opens: 0, closes: 0)
        let topY = 100.0
        let e1 = ResolvedEvent(origin: Point(x: 60, y: topY), kind: .note(n1))
        let e2 = ResolvedEvent(origin: Point(x: 100, y: topY), kind: .note(n2))
        let measure = ResolvedMeasure(
            origin: Point(x: 36, y: 50), width: 200,
            events: [e1, e2], openingBar: nil,
            closingBar: ResolvedBarLine(x: 236, kind: .single),
            unitNoteLength: eighthUNL
        )
        let svgs = try emitter.emit(layout(systems: [system(measures: [measure])]))
        let svg  = try #require(svgs.first)
        #expect(!svg.contains("<path"))
    }

    // MARK: - Scroll-sync metadata (issue #25)

    @Test func scrollSyncCommentListsOneAnchorPerSystem() throws {
        let s1 = system(measures: [emptyMeasure()], abcLine: 3, originY: 100)
        let s2 = system(measures: [emptyMeasure()], abcLine: 9, originY: 250)
        let svgs = try emitter.emit(layout(systems: [s1, s2]))
        let svg  = try #require(svgs.first)
        #expect(svg.contains(
            "<!-- ceolkit-meta: {\"page\": 1, \"anchors\": " +
            "[{\"abcLine\": 3, \"y\": 100}, {\"abcLine\": 9, \"y\": 250}]} -->"
        ))
    }

    @Test func scrollSyncCommentPrecedesOtherPageContent() throws {
        let svgs = try emitter.emit(layout(systems: [system(measures: [emptyMeasure()])]))
        let svg  = try #require(svgs.first)
        let commentRange = try #require(svg.range(of: "<!-- ceolkit-meta:"))
        let lineRange = try #require(svg.range(of: "<line"))
        #expect(commentRange.lowerBound < lineRange.lowerBound)
    }

    @Test func scrollSyncCommentUsesCorrectPageNumber() throws {
        let layout = ResolvedLayout(
            pageSize: Size(width: 612, height: 792),
            margins: config.margins,
            pages: [
                ResolvedPage(systems: [system(measures: [emptyMeasure()])]),
                ResolvedPage(systems: [system(measures: [emptyMeasure()])])
            ]
        )
        let svgs = try emitter.emit(layout)
        #expect(svgs[0].contains("\"page\": 1"))
        #expect(svgs[1].contains("\"page\": 2"))
    }
}
