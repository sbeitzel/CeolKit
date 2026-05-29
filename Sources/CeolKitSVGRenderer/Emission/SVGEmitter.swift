import CeolKitModel
import Foundation

// MARK: - Error

enum SVGEmitterError: Error {
    case bravuraFontNotFound
}

// MARK: - Pass 5

/// Pass 5: converts a `ResolvedLayout` into one self-contained SVG document per page.
///
/// Each SVG embeds Bravura as a base64 `@font-face` source so the output is
/// fully self-contained regardless of the viewer's font environment.
struct SVGEmitter: Sendable {
    let config: SVGRenderConfig
    let metadata: BravuraMetadata

    // MARK: - Public entry point

    func emit(_ layout: ResolvedLayout) throws -> [String] {
        let base64 = try loadBravuraBase64()
        return layout.pages.map { emitPage($0, layout: layout, bravuraBase64: base64) }
    }

    // MARK: - Page

    private func emitPage(_ page: ResolvedPage, layout: ResolvedLayout, bravuraBase64: String) -> String {
        var builder = SVGBuilder()
        for system in page.systems {
            emitSystem(system, builder: &builder)
        }
        return builder.buildDocument(
            width: layout.pageSize.width,
            height: layout.pageSize.height,
            bravuraBase64: bravuraBase64
        )
    }

    // MARK: - System

    private func emitSystem(_ system: ResolvedSystem, builder: inout SVGBuilder) {
        emitStaffLines(system, builder: &builder)
        emitClef(system, builder: &builder)
        for measure in system.measures {
            emitMeasure(measure, system: system, builder: &builder)
        }
    }

    private func emitStaffLines(_ system: ResolvedSystem, builder: inout SVGBuilder) {
        guard let lastMeasure = system.measures.last else { return }
        let topY      = system.origin.y + system.staffOrigin
        let leftX     = system.origin.x
        let rightX    = lastMeasure.origin.x + lastMeasure.width
        let thickness = metadata.engravingDefaults.staffLineThickness * config.staffSize
        for i in 0..<5 {
            let y = topY + Double(i) * config.staffSize
            builder.line(x1: leftX, y1: y, x2: rightX, y2: y,
                         stroke: "black", strokeWidth: thickness)
        }
    }

    // MARK: - Clef

    private func emitClef(_ system: ResolvedSystem, builder: inout SVGBuilder) {
        guard let glyph = clefGlyph(for: system.clef.clef) else { return }
        let s = config.staffSize
        let bottomStaffY = system.origin.y + system.staffOrigin + system.staffHeight
        let fontSize = 4.0 * s
        let x = system.origin.x + 0.25 * s
        let y: Double
        switch system.clef.clef {
        case .none:                 return
        case .treble:               y = bottomStaffY - s
        case .bass, .baritone:      y = bottomStaffY - 3 * s
        case .alto:                 y = bottomStaffY - 2 * s
        case .tenor:                y = bottomStaffY - 3 * s
        case .soprano:              y = bottomStaffY
        case .mezzoSoprano:         y = bottomStaffY - s
        case .percussion:           y = bottomStaffY - 2 * s
        }
        builder.text(String(glyph.character), x: x, y: y, fontFamily: "Bravura", fontSize: fontSize)
    }

    private func clefGlyph(for clef: Clef) -> SMuFLGlyph? {
        switch clef {
        case .none:                 return nil
        case .treble:               return .gClef
        case .bass, .baritone:      return .fClef
        case .alto, .tenor, .soprano, .mezzoSoprano: return .cClef
        case .percussion:           return .unpitchedPercussionClef1
        }
    }

    // MARK: - Measure

    private func emitMeasure(_ measure: ResolvedMeasure, system: ResolvedSystem, builder: inout SVGBuilder) {
        let topY    = system.origin.y + system.staffOrigin
        let bottomY = topY + system.staffHeight

        if let opening = measure.openingBar {
            emitBarLine(opening, topY: topY, bottomY: bottomY, builder: &builder)
        }
        emitBarLine(measure.closingBar, topY: topY, bottomY: bottomY, builder: &builder)

        for event in measure.events {
            emitEvent(event, topStaffY: topY, bottomStaffY: bottomY,
                      unitNoteLength: measure.unitNoteLength, builder: &builder)
        }
    }

    // MARK: - Bar lines

    private func emitBarLine(_ bar: ResolvedBarLine, topY: Double, bottomY: Double,
                              builder: inout SVGBuilder) {
        let thin  = metadata.engravingDefaults.thinBarlineThickness  * config.staffSize
        let thick = metadata.engravingDefaults.thickBarlineThickness * config.staffSize
        let sep   = metadata.engravingDefaults.barlineSeparation     * config.staffSize

        switch bar.kind {
        case .single, .dotted:
            builder.line(x1: bar.x, y1: topY, x2: bar.x, y2: bottomY,
                         stroke: "black", strokeWidth: thin)

        case .double:
            builder.line(x1: bar.x,       y1: topY, x2: bar.x,       y2: bottomY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x + sep, y1: topY, x2: bar.x + sep, y2: bottomY,
                         stroke: "black", strokeWidth: thin)

        case .final:
            builder.line(x1: bar.x,        y1: topY, x2: bar.x,        y2: bottomY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x + sep,  y1: topY, x2: bar.x + sep,  y2: bottomY,
                         stroke: "black", strokeWidth: thick)

        case .start:
            builder.line(x1: bar.x,       y1: topY, x2: bar.x,       y2: bottomY,
                         stroke: "black", strokeWidth: thick)
            builder.line(x1: bar.x + sep, y1: topY, x2: bar.x + sep, y2: bottomY,
                         stroke: "black", strokeWidth: thin)

        case .repeatEnd, .repeatStart, .repeatBoth:
            // Simplified: render as a double bar; dots are deferred to a future pass.
            builder.line(x1: bar.x,       y1: topY, x2: bar.x,       y2: bottomY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x + sep, y1: topY, x2: bar.x + sep, y2: bottomY,
                         stroke: "black", strokeWidth: thick)
        }
    }

    // MARK: - Events

    private func emitEvent(_ event: ResolvedEvent, topStaffY: Double, bottomStaffY: Double,
                           unitNoteLength: Fraction, builder: inout SVGBuilder) {
        switch event.kind {
        case .note(let n):
            emitNote(n, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                     unitNoteLength: unitNoteLength, builder: &builder)
        case .rest(let r):
            emitRest(r, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                     unitNoteLength: unitNoteLength, builder: &builder)
        case .chord(let c):
            for note in c.notes {
                emitNote(note, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                         unitNoteLength: unitNoteLength, builder: &builder)
            }
        case .grace(let g):
            emitGraceGroup(g, originX: event.origin.x, topStaffY: topStaffY,
                           bottomStaffY: bottomStaffY, builder: &builder)
        case .tuplet, .spacer, .directiveAnchor:
            break // deferred to a future pass
        }
    }

    // MARK: - Notes

    private func emitNote(_ note: Note, x: Double, topStaffY: Double, bottomStaffY: Double,
                          unitNoteLength: Fraction, builder: inout SVGBuilder) {
        let staffPos  = self.staffPos(for: note.pitch)
        let y         = noteY(staffPos: staffPos, bottomStaffY: bottomStaffY)
        let absDur    = absoluteDuration(note.duration, unitNoteLength: unitNoteLength)
        let glyph     = noteheadGlyph(absoluteDuration: absDur)
        let fontSize  = 4.0 * config.staffSize

        builder.text(String(glyph.character), x: x, y: y,
                     fontFamily: "Bravura", fontSize: fontSize)

        if let acc = note.displayedAccidental {
            emitAccidental(acc, x: x, y: y, fontSize: fontSize, builder: &builder)
        }

        if absDur < 1.0 {
            emitStem(staffPos: staffPos, noteheadY: y, x: x, absDur: absDur,
                     beamState: note.beam, builder: &builder)
        }

        emitLedgerLines(staffPos: staffPos, x: x, bottomStaffY: bottomStaffY, builder: &builder)
    }

    private func emitStem(staffPos: Int, noteheadY: Double, x: Double, absDur: Double,
                           beamState: BeamState, builder: inout SVGBuilder) {
        let stemUp       = staffPos <= 4
        let noteheadW    = noteheadWidth()
        let stemThick    = metadata.engravingDefaults.stemThickness * config.staffSize
        let stemLength   = 3.5 * config.staffSize

        let stemX: Double
        let stemTop: Double
        let stemBottom: Double

        if stemUp {
            stemX      = x + noteheadW
            stemTop    = noteheadY - stemLength
            stemBottom = noteheadY
        } else {
            stemX      = x
            stemTop    = noteheadY
            stemBottom = noteheadY + stemLength
        }

        builder.line(x1: stemX, y1: stemTop, x2: stemX, y2: stemBottom,
                     stroke: "black", strokeWidth: stemThick)

        // Flags (only for un-beamed notes shorter than a quarter)
        if absDur < 0.25 && beamState == .single {
            let flagY    = stemUp ? stemTop : stemBottom
            let fontSize = 4.0 * config.staffSize
            let flag     = flagGlyph(absDur: absDur, stemUp: stemUp)
            builder.text(String(flag.character), x: stemX, y: flagY,
                         fontFamily: "Bravura", fontSize: fontSize)
        }
    }

    private func emitAccidental(_ alt: Alteration, x: Double, y: Double,
                                fontSize: Double, builder: inout SVGBuilder) {
        guard let glyph = accidentalGlyph(for: alt) else { return }
        let accWidth = config.staffSize * 0.75
        builder.text(String(glyph.character), x: x - accWidth, y: y,
                     fontFamily: "Bravura", fontSize: fontSize)
    }

    private func emitLedgerLines(staffPos: Int, x: Double, bottomStaffY: Double,
                                 scale: Double = 1.0, builder: inout SVGBuilder) {
        let s         = config.staffSize
        let ext       = metadata.engravingDefaults.legerLineExtension * s * scale
        let thickness = metadata.engravingDefaults.legerLineThickness * s * scale
        let noteW     = noteheadWidth() * scale

        if staffPos > 8 {
            var p = 10
            while p <= staffPos {
                let ly = bottomStaffY - Double(p) * s / 2.0
                builder.line(x1: x - ext, y1: ly, x2: x + noteW + ext, y2: ly,
                             stroke: "black", strokeWidth: thickness)
                p += 2
            }
        }
        if staffPos < 0 {
            var p = -2
            while p >= staffPos {
                let ly = bottomStaffY - Double(p) * s / 2.0
                builder.line(x1: x - ext, y1: ly, x2: x + noteW + ext, y2: ly,
                             stroke: "black", strokeWidth: thickness)
                p -= 2
            }
        }
    }

    // MARK: - Grace groups

    /// Scale factor for grace note glyphs and geometry relative to normal notes.
    private let graceScale = 0.6

    private func emitGraceGroup(_ grace: GraceGroup, originX: Double,
                                 topStaffY: Double, bottomStaffY: Double,
                                 builder: inout SVGBuilder) {
        guard !grace.notes.isEmpty else { return }

        let s          = config.staffSize
        let fontSize   = 4.0 * s * graceScale
        let stemThick  = metadata.engravingDefaults.stemThickness * s
        let noteW      = noteheadWidth() * graceScale
        let colWidth   = noteW * 1.5   // total column per grace note: 0.25W lead + W head + 0.25W trail
        let stemLength = 3.5 * s * graceScale
        let multiple   = grace.notes.count > 1

        // Pre-pass: compute notehead Y and stem X for each grace note.
        // Each note's notehead is offset 0.25 × noteW into its column so adjacent noteheads
        // have 0.5 × noteW of breathing room between them.
        // Grace note stems always point up, so the stem X is at the right edge of the notehead.
        struct GracePos { let x, noteheadY, stemX: Double; let staffPos: Int }
        let positions: [GracePos] = grace.notes.enumerated().map { i, note in
            let x   = originX + Double(i) * colWidth + noteW * 0.25
            let sp  = self.staffPos(for: note.pitch)
            let y   = noteY(staffPos: sp, bottomStaffY: bottomStaffY)
            return GracePos(x: x, noteheadY: y, stemX: x + noteW, staffPos: sp)
        }

        // The beam (or flag) sits at the top of the highest note's stem.
        // All other stems are extended upward to meet that same Y.
        let highestNoteheadY = positions.map(\.noteheadY).min() ?? positions[0].noteheadY
        var beamY            = highestNoteheadY - stemLength

        // For beamed groups, ensure all three beams clear the top staff line.
        // Clamp beamY so the bottom beam (index 2) sits one beamStep above the top staff line,
        // matching the visual gap between adjacent beams.
        if multiple {
            let beamThick   = metadata.engravingDefaults.beamThickness * s * graceScale
            let beamSpacing = metadata.engravingDefaults.beamSpacing   * s * graceScale
            let beamStep    = beamThick + beamSpacing
            beamY = min(beamY, topStaffY - 3.0 * beamStep)
        }

        for (i, pos) in positions.enumerated() {
            let note = grace.notes[i]

            builder.text(String(SMuFLGlyph.noteheadBlack.character), x: pos.x, y: pos.noteheadY,
                         fontFamily: "Bravura", fontSize: fontSize)

            if let acc = note.displayedAccidental, let glyph = accidentalGlyph(for: acc) {
                builder.text(String(glyph.character), x: pos.x - s * 0.75 * graceScale, y: pos.noteheadY,
                             fontFamily: "Bravura", fontSize: fontSize)
            }

            // Stem runs from the notehead up to beamY; the highest note has exactly stemLength,
            // lower notes are extended so every stem tip meets the beam.
            builder.line(x1: pos.stemX, y1: beamY, x2: pos.stemX, y2: pos.noteheadY,
                         stroke: "black", strokeWidth: stemThick)

            // Single grace note gets a 32nd-note flag (three flags)
            if !multiple {
                builder.text(String(SMuFLGlyph.flag32ndUp.character), x: pos.stemX, y: beamY,
                             fontFamily: "Bravura", fontSize: fontSize)
            }

            emitLedgerLines(staffPos: pos.staffPos, x: pos.x, bottomStaffY: bottomStaffY,
                            scale: graceScale, builder: &builder)
        }

        // Three beams for a beamed grace group (32nd-note visual convention).
        // Beams stack downward from beamY (toward the noteheads) spaced by beamThickness + beamSpacing.
        if multiple, let first = positions.first, let last = positions.last {
            let beamThick   = metadata.engravingDefaults.beamThickness * s * graceScale
            let beamSpacing = metadata.engravingDefaults.beamSpacing   * s * graceScale
            let beamStep    = beamThick + beamSpacing
            for b in 0..<3 {
                let y = beamY + Double(b) * beamStep
                builder.line(x1: first.stemX, y1: y, x2: last.stemX, y2: y,
                             stroke: "black", strokeWidth: beamThick)
            }
        }

        // Acciaccatura: diagonal slash through the first stem at its midpoint
        if grace.kind == .acciaccatura, let first = positions.first {
            let midStemY = (first.noteheadY + beamY) / 2.0
            let slashExt = s * 0.25
            builder.line(x1: first.stemX - slashExt, y1: midStemY + slashExt,
                         x2: first.stemX + slashExt, y2: midStemY - slashExt,
                         stroke: "black", strokeWidth: stemThick)
        }
    }

    // MARK: - Rests

    private func emitRest(_ rest: Rest, x: Double, topStaffY: Double, bottomStaffY: Double,
                          unitNoteLength: Fraction, builder: inout SVGBuilder) {
        switch rest.kind {
        case .invisible, .fullMeasureInvisible: return
        default: break
        }

        let absDur   = rest.kind == .fullMeasure ? 1.0 :
                       absoluteDuration(rest.duration, unitNoteLength: unitNoteLength)
        let fontSize = 4.0 * config.staffSize
        let s        = config.staffSize

        let glyph: SMuFLGlyph
        let y: Double

        if absDur >= 1.0 {
            glyph = .restWhole
            // Whole rest hangs below 4th staff line (staffPos 6); glyph baseline at that line.
            y = bottomStaffY - 6.0 * s / 2.0
        } else if absDur >= 0.5 {
            glyph = .restHalf
            y = bottomStaffY - 4.0 * s / 2.0   // sits on middle line
        } else if absDur >= 0.25 {
            glyph = .restQuarter
            y = bottomStaffY - 4.0 * s / 2.0
        } else if absDur >= 0.125 {
            glyph = .rest8th
            y = bottomStaffY - 4.0 * s / 2.0
        } else if absDur >= 0.0625 {
            glyph = .rest16th
            y = bottomStaffY - 4.0 * s / 2.0
        } else if absDur >= 0.03125 {
            glyph = .rest32nd
            y = bottomStaffY - 4.0 * s / 2.0
        } else {
            glyph = .rest64th
            y = bottomStaffY - 4.0 * s / 2.0
        }

        builder.text(String(glyph.character), x: x, y: y,
                     fontFamily: "Bravura", fontSize: fontSize)
    }

    // MARK: - Helpers

    private func staffPos(for pitch: Pitch) -> Int {
        (pitch.octave - 4) * 7 + (pitch.step.rawValue - DiatonicStep.e.rawValue)
    }

    private func noteY(staffPos: Int, bottomStaffY: Double) -> Double {
        bottomStaffY - Double(staffPos) * config.staffSize / 2.0
    }

    private func absoluteDuration(_ duration: Fraction, unitNoteLength: Fraction) -> Double {
        let d   = Double(duration.numerator)   / Double(duration.denominator)
        let unl = Double(unitNoteLength.numerator) / Double(unitNoteLength.denominator)
        return d * unl
    }

    private func noteheadGlyph(absoluteDuration d: Double) -> SMuFLGlyph {
        if d >= 1.0 { return .noteheadWhole }
        if d >= 0.5 { return .noteheadHalf  }
        return .noteheadBlack
    }

    private func flagGlyph(absDur: Double, stemUp: Bool) -> SMuFLGlyph {
        if absDur >= 0.125 { return stemUp ? .flag8thUp  : .flag8thDown  }
        if absDur >= 0.0625 { return stemUp ? .flag16thUp : .flag16thDown }
        return stemUp ? .flag32ndUp : .flag32ndDown
    }

    private func accidentalGlyph(for alt: Alteration) -> SMuFLGlyph? {
        switch (alt.numerator, alt.denominator) {
        case (1, 1):  return .accidentalSharp
        case (-1, 1): return .accidentalFlat
        case (0, _):  return .accidentalNatural
        case (2, 1):  return .accidentalDoubleSharp
        case (-2, 1): return .accidentalDoubleFlat
        default:      return nil  // microtonal — no glyph in v0.1 set
        }
    }

    private func noteheadWidth() -> Double {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
            ?? config.staffSize * 1.2
    }

    private func loadBravuraBase64() throws -> String {
        guard let url = Bundle.module.url(forResource: "Bravura", withExtension: "otf") else {
            throw SVGEmitterError.bravuraFontNotFound
        }
        let data = try Data(contentsOf: url)
        return data.base64EncodedString()
    }
}
