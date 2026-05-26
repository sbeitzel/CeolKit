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
private func system(measures: [ResolvedMeasure]) -> ResolvedSystem {
    let staffHeight = 4.0 * config.staffSize
    return ResolvedSystem(
        origin: Point(x: config.margins.left, y: 50),
        measures: measures,
        staffOrigin: 50,
        staffHeight: staffHeight,
        extraAbove: 50,
        extraBelow: 0,
        totalHeight: 50 + staffHeight
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
        #expect(svg.contains("font-family: 'Bravura'"))
        #expect(svg.contains("data:font/otf;base64,"))
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
}
