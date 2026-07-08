import CeolKitModel
import Foundation

// MARK: - Error

enum SVGEmitterError: Error {
    case bravuraFontNotFound
}

// MARK: - Internal geometry

/// Stem geometry returned by `emitStem` so the caller can draw beam strokes.
private struct StemInfo {
    let stemX:     Double  // x of the stem stroke
    let stemTipY:  Double  // y of the tip (the end away from the notehead)
    let stemUp:    Bool
    let noteheadY: Double  // y of the notehead end (used by emitBeamGroup to draw stems)
}

/// Pending tie: records where a tied note's arc must start so the arc can be drawn
/// when the matching end note is encountered (possibly in the next measure).
private struct TieAnchor {
    let x: Double       // left-edge x of the notehead where the tie originates
    let noteY: Double   // y of the notehead
    let pitch: Pitch    // matched against the end note's pitch
    let staffPos: Int   // determines whether the arc curves above or below the note
}

/// Pending slur: records the start position of an open slur bracket so the arc
/// can be drawn when the matching closing `)` note is encountered.  Stored as a
/// LIFO stack so that nested slurs resolve correctly (innermost closes first).
private struct SlurAnchor {
    let x: Double       // left-edge x of the notehead where the slur opens
    let noteY: Double   // y of the notehead
    let staffPos: Int   // determines whether the arc curves above or below
}

// MARK: - Pass 5

/// Pass 5: converts a `ResolvedLayout` into one self-contained SVG document per page.
///
/// Each SVG embeds Bravura as a base64 `@font-face` source so the output is
/// fully self-contained regardless of the viewer's font environment.
struct SVGEmitter: Sendable {
    let config: SVGRenderConfig
    let metadata: BravuraMetadata
    let stemDirection: StemDirection

    init(config: SVGRenderConfig, metadata: BravuraMetadata, stemDirection: StemDirection = .auto) {
        self.config = config
        self.metadata = metadata
        self.stemDirection = stemDirection
    }

    // MARK: - Public entry point

    func emit(_ layout: ResolvedLayout) throws -> [String] {
        let bravuraBase64             = try loadBravuraBase64()
        let libertinusSerifBase64     = try LibertinusSerifMetrics.loadBase64()
        let libertinusSerifItalicBase64 = try LibertinusSerifMetrics.loadItalicBase64()
        return layout.pages.enumerated().map { pageIndex, page in
            emitPage(page, pageNumber: pageIndex + 1, layout: layout,
                     bravuraBase64: bravuraBase64,
                     libertinusSerifBase64: libertinusSerifBase64,
                     libertinusSerifItalicBase64: libertinusSerifItalicBase64)
        }
    }

    // MARK: - Page

    private func emitPage(_ page: ResolvedPage, pageNumber: Int, layout: ResolvedLayout,
                           bravuraBase64: String,
                           libertinusSerifBase64: String,
                           libertinusSerifItalicBase64: String) -> String {
        var builder = SVGBuilder()
        emitScrollSyncMetadata(for: page, pageNumber: pageNumber, builder: &builder)
        emitTitleBlock(page.titleRows, builder: &builder)
        for system in page.systems {
            emitSystem(system, builder: &builder)
        }
        emitFooterBlock(page.footerRows, builder: &builder)
        return builder.buildDocument(
            width: layout.pageSize.width,
            height: layout.pageSize.height,
            bravuraBase64: bravuraBase64,
            libertinusSerifBase64: libertinusSerifBase64,
            libertinusSerifItalicBase64: libertinusSerifItalicBase64
        )
    }

    // MARK: - Scroll-sync metadata

    /// Emits the `ceolkit-meta` comment (issue #25) listing each staff system's
    /// originating ABC source line and page Y coordinate, so editor consumers
    /// (e.g. ScoreEdit) can synchronise scroll position with the source.
    private func emitScrollSyncMetadata(for page: ResolvedPage, pageNumber: Int, builder: inout SVGBuilder) {
        let anchors = page.systems.map { system in
            "{\"abcLine\": \(system.abcLine), \"y\": \(builder.fmt(system.origin.y))}"
        }.joined(separator: ", ")
        builder.comment("ceolkit-meta: {\"page\": \(pageNumber), \"anchors\": [\(anchors)]}")
    }

    // MARK: - Title block

    private func emitTitleBlock(_ rows: [ResolvedTitleRow], builder: inout SVGBuilder) {
        for row in rows {
            for item in row.items {
                builder.text(
                    item.text,
                    x: item.x,
                    y: item.baselineY,
                    fontFamily: "Libertinus Serif",
                    fontSize: item.fontSize,
                    textAnchor: item.anchor.rawValue,
                    fontStyle: item.isItalic ? "italic" : nil
                )
            }
        }
    }

    // MARK: - Footer block

    private func emitFooterBlock(_ rows: [ResolvedTitleRow], builder: inout SVGBuilder) {
        for row in rows {
            for item in row.items {
                builder.text(
                    item.text,
                    x: item.x,
                    y: item.baselineY,
                    fontFamily: "Libertinus Serif",
                    fontSize: item.fontSize,
                    textAnchor: item.anchor.rawValue,
                    className: "footer"
                )
            }
        }
    }

    // MARK: - System

    private func emitSystem(_ system: ResolvedSystem, builder: inout SVGBuilder) {
        emitStaffLines(system, builder: &builder)
        emitClef(system, builder: &builder)
        if let keySig = system.keySignature {
            emitKeySignature(keySig, system: system, builder: &builder)
        }
        if let meter = system.meter {
            emitTimeSignature(meter, system: system, builder: &builder)
        }
        var pendingTies:  [TieAnchor]  = []
        var pendingSlurs: [SlurAnchor] = []  // LIFO: innermost slur closes first
        for measure in system.measures {
            emitMeasure(measure, system: system,
                        pendingTies: &pendingTies, pendingSlurs: &pendingSlurs,
                        builder: &builder)
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

    // MARK: - Key signature

    private func emitKeySignature(_ keySig: KeySignature, system: ResolvedSystem,
                                  builder: inout SVGBuilder) {
        let accs = keyAccidentals(for: keySig)
        guard !accs.isEmpty else { return }

        let s            = config.staffSize
        let fontSize     = 4.0 * s
        let bottomStaffY = system.origin.y + system.staffOrigin + system.staffHeight
        let glyphW       = metadata.glyphBBoxes["accidentalSharp"].map { $0.width * s } ?? s * 0.75
        let gap          = s * 0.1
        let startX       = system.origin.x + clefWidth(for: system.clef.clef)

        for (i, acc) in accs.enumerated() {
            let x = startX + Double(i) * (glyphW + gap)
            let y = noteY(staffPos: acc.staffPosition, bottomStaffY: bottomStaffY)
            builder.text(String(acc.glyph.character), x: x, y: y,
                         fontFamily: "Bravura", fontSize: fontSize)
        }
    }

    // MARK: - Time signature

    private func emitTimeSignature(_ meter: Meter, system: ResolvedSystem, builder: inout SVGBuilder) {
        let s = config.staffSize
        let keySigW = system.keySignature.map {
            keySignatureWidth(for: $0, metadata: metadata, staffSize: s)
        } ?? 0
        let startX = system.origin.x + clefWidth(for: system.clef.clef) + keySigW
        emitTimeSignatureGlyph(meter, atX: startX, system: system, builder: &builder)
    }

    private func emitTimeSignatureGlyph(_ meter: Meter, atX startX: Double,
                                        system: ResolvedSystem, builder: inout SVGBuilder) {
        let s = config.staffSize
        let fontSize = 4.0 * s
        let bottomStaffY = system.origin.y + system.staffOrigin + system.staffHeight

        switch meter {
        case .commonTime:
            builder.text(String(SMuFLGlyph.timeSigCommon.character), x: startX,
                         y: bottomStaffY - 2.0 * s, fontFamily: "Bravura", fontSize: fontSize)
        case .cutTime:
            builder.text(String(SMuFLGlyph.timeSigCutCommon.character), x: startX,
                         y: bottomStaffY - 2.0 * s, fontFamily: "Bravura", fontSize: fontSize)
        case .fraction(let num, let den):
            emitTimeSigNumber(num, x: startX, y: bottomStaffY - 3.0 * s,
                              fontSize: fontSize, builder: &builder)
            emitTimeSigNumber(den, x: startX, y: bottomStaffY - s,
                              fontSize: fontSize, builder: &builder)
        case .free, .complex:
            break
        }
    }

    private func emitTimeSigNumber(_ n: Int, x: Double, y: Double, fontSize: Double,
                                   builder: inout SVGBuilder) {
        let glyphW = metadata.glyphBBoxes["timeSig4"].map { $0.width * config.staffSize }
            ?? config.staffSize * 0.9
        for (i, digit) in String(n).enumerated() {
            guard let d = digit.wholeNumberValue, let glyph = timeSigDigitGlyph(d) else { continue }
            builder.text(String(glyph.character), x: x + Double(i) * glyphW, y: y,
                         fontFamily: "Bravura", fontSize: fontSize)
        }
    }

    private func timeSigDigitGlyph(_ d: Int) -> SMuFLGlyph? {
        switch d {
        case 0: return .timeSig0
        case 1: return .timeSig1
        case 2: return .timeSig2
        case 3: return .timeSig3
        case 4: return .timeSig4
        case 5: return .timeSig5
        case 6: return .timeSig6
        case 7: return .timeSig7
        case 8: return .timeSig8
        case 9: return .timeSig9
        default: return nil
        }
    }

    /// Width consumed by the clef glyph plus its right-side padding.
    private func clefWidth(for clef: Clef) -> Double {
        let name: String
        switch clef {
        case .none:                              return 0
        case .treble:                            name = "gClef"
        case .bass, .baritone:                  name = "fClef"
        case .alto, .tenor, .soprano, .mezzoSoprano: name = "cClef"
        case .percussion:                        name = "unpitchedPercussionClef1"
        }
        let glyphWidth = metadata.glyphBBoxes[name].map { $0.width * config.staffSize }
            ?? (2.8 * config.staffSize)
        return glyphWidth + 0.5 * config.staffSize
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

    private func emitMeasure(_ measure: ResolvedMeasure, system: ResolvedSystem,
                              pendingTies: inout [TieAnchor], pendingSlurs: inout [SlurAnchor],
                              builder: inout SVGBuilder) {
        let topY    = system.origin.y + system.staffOrigin
        let bottomY = topY + system.staffHeight

        if let opening = measure.openingBar {
            emitBarLine(opening, topY: topY, bottomY: bottomY, builder: &builder)
        }
        emitBarLine(measure.closingBar, topY: topY, bottomY: bottomY, builder: &builder)

        if let meter = measure.meter {
            let thin = metadata.engravingDefaults.thinBarlineThickness * config.staffSize
            emitTimeSignatureGlyph(meter, atX: measure.origin.x + 2.0 * thin,
                                   system: system, builder: &builder)
        }

        // Beam accumulator: per-note (StemInfo, beamCount) pairs for the current beam run.
        var pendingBeam: [(stem: StemInfo, beamCount: Int)]?
        // Grace note beam tip Y for the note that immediately follows; reset after each non-grace event.
        var lastGraceBeamY: Double? = nil

        func flushBeam() {
            guard let g = pendingBeam else { return }
            emitBeamGroup(g, builder: &builder)
            pendingBeam = nil
        }

        for event in measure.events {
            // Grace events are handled here so their stem-tip Y can be forwarded
            // to the next note for fermata clearance.
            if case .grace(let g) = event.kind {
                lastGraceBeamY = emitGraceGroup(g, originX: event.origin.x, topStaffY: topY,
                                                bottomStaffY: bottomY, builder: &builder)
                continue
            }
            let stemInfo = emitEvent(event, topStaffY: topY, bottomStaffY: bottomY,
                                     unitNoteLength: measure.unitNoteLength,
                                     precedingGraceBeamY: lastGraceBeamY,
                                     builder: &builder)
            lastGraceBeamY = nil
            if let info = stemInfo, let note = noteFrom(event) {
                let bc = requiredBeamCount(absoluteDuration(note.duration,
                                                            unitNoteLength: measure.unitNoteLength))
                let entry = (stem: info, beamCount: bc)
                switch note.beam {
                case .start:
                    flushBeam()  // safety: shouldn't have an open group here
                    pendingBeam = [entry]
                case .middle:
                    pendingBeam?.append(entry)
                case .end:
                    pendingBeam?.append(entry)
                    flushBeam()
                case .single:
                    break
                }
            }

            // Tie handling: resolve incoming ties before recording outgoing ones so that
            // a .continuesTie note draws the arc from the previous note to itself and
            // then registers itself as a new tie start.
            if let note = noteFrom(event), note.ties != .none {
                let sp = staffPos(for: note.pitch)
                let ny = noteY(staffPos: sp, bottomStaffY: bottomY)

                if note.ties == .endsTie || note.ties == .continuesTie {
                    if let idx = pendingTies.firstIndex(where: { $0.pitch == note.pitch }) {
                        let anchor = pendingTies.remove(at: idx)
                        emitTieArc(fromX: anchor.x, fromY: anchor.noteY, staffPos: anchor.staffPos,
                                   toX: event.origin.x, toY: ny, builder: &builder)
                    }
                }
                if note.ties == .startsTie || note.ties == .continuesTie {
                    pendingTies.append(TieAnchor(x: event.origin.x, noteY: ny,
                                                 pitch: note.pitch, staffPos: sp))
                }
            }

            // Slur handling: close slurs first (innermost first, LIFO), then open new ones.
            // A slur arc is visually identical to a tie arc; the difference is semantic.
            if let note = noteFrom(event), note.slurs.opens > 0 || note.slurs.closes > 0 {
                let sp = staffPos(for: note.pitch)
                let ny = noteY(staffPos: sp, bottomStaffY: bottomY)

                for _ in 0..<note.slurs.closes {
                    if let anchor = pendingSlurs.popLast() {
                        emitTieArc(fromX: anchor.x, fromY: anchor.noteY, staffPos: anchor.staffPos,
                                   toX: event.origin.x, toY: ny, builder: &builder)
                    }
                }
                for _ in 0..<note.slurs.opens {
                    pendingSlurs.append(SlurAnchor(x: event.origin.x, noteY: ny, staffPos: sp))
                }
            }
        }
        flushBeam()  // safety flush for malformed input
    }

    private func noteFrom(_ event: ResolvedEvent) -> Note? {
        if case .note(let n) = event.kind { return n }
        return nil
    }

    private func requiredBeamCount(_ absDur: Double) -> Int {
        if absDur < 0.03125 { return 4 }  // 64th
        if absDur < 0.0625  { return 3 }  // 32nd
        if absDur < 0.125   { return 2 }  // 16th
        return 1                           // eighth
    }

    private func emitBeamGroup(_ entries: [(stem: StemInfo, beamCount: Int)],
                               builder: inout SVGBuilder) {
        guard entries.count >= 2 else { return }
        let first = entries.first!.stem
        let stems = entries.map(\.stem)

        let s         = config.staffSize
        let beamThick = metadata.engravingDefaults.beamThickness * s
        let beamStep  = (metadata.engravingDefaults.beamThickness + metadata.engravingDefaults.beamSpacing) * s
        let stemThick = metadata.engravingDefaults.stemThickness * s

        let stemUp = first.stemUp
        // Common beam Y: for stem-up, the highest tip (min Y); for stem-down, the lowest tip (max Y).
        let commonBeamY = stemUp
            ? stems.map(\.stemTipY).min()!
            : stems.map(\.stemTipY).max()!

        // Draw each stem from its notehead to the common beam Y.
        for stem in stems {
            let (y1, y2) = stemUp
                ? (commonBeamY, stem.noteheadY)
                : (stem.noteheadY, commonBeamY)
            builder.line(x1: stem.stemX, y1: y1, x2: stem.stemX, y2: y2,
                         stroke: "black", strokeWidth: stemThick)
        }

        // Draw beam levels. Level 0 always spans all notes. Higher levels span only
        // consecutive notes with sufficient beam count; isolated notes at a higher level
        // get a stub beam pointing toward the nearest neighbor.
        let maxBeams = entries.map(\.beamCount).max() ?? 1
        for b in 0..<maxBeams {
            let beamY = stemUp
                ? commonBeamY + Double(b) * beamStep
                : commonBeamY - Double(b) * beamStep

            func emitRun(from start: Int, to end: Int) {
                if start < end {
                    builder.line(x1: entries[start].stem.stemX, y1: beamY,
                                 x2: entries[end].stem.stemX,   y2: beamY,
                                 stroke: "black", strokeWidth: beamThick)
                } else {
                    // Stub: point right if first in group, otherwise left.
                    // Cap at 0.75 × staffSize so grace-note-inflated inter-stem distances
                    // don't produce excessively long stubs.
                    let stemX = entries[start].stem.stemX
                    let maxStubW = s * 0.75
                    if start == 0 {
                        let stubW = min((entries[1].stem.stemX - stemX) * 0.5, maxStubW)
                        builder.line(x1: stemX, y1: beamY, x2: stemX + stubW, y2: beamY,
                                     stroke: "black", strokeWidth: beamThick)
                    } else {
                        let stubW = min((stemX - entries[start - 1].stem.stemX) * 0.5, maxStubW)
                        builder.line(x1: stemX - stubW, y1: beamY, x2: stemX, y2: beamY,
                                     stroke: "black", strokeWidth: beamThick)
                    }
                }
            }

            var runStart: Int? = nil
            for i in 0..<entries.count {
                if entries[i].beamCount > b {
                    if runStart == nil { runStart = i }
                } else if let start = runStart {
                    emitRun(from: start, to: i - 1)
                    runStart = nil
                }
            }
            if let start = runStart {
                emitRun(from: start, to: entries.count - 1)
            }
        }
    }

    // MARK: - Bar lines

    private func emitBarLine(_ bar: ResolvedBarLine, topY: Double, bottomY: Double,
                              builder: inout SVGBuilder) {
        let thin    = metadata.engravingDefaults.thinBarlineThickness  * config.staffSize
        let thick   = metadata.engravingDefaults.thickBarlineThickness * config.staffSize
        let sep     = metadata.engravingDefaults.barlineSeparation     * config.staffSize
        let wideSep = sep * 2.0

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
            // Right-anchored: thick bar trailing edge at bar.x, thin bar to its left.
            builder.line(x1: bar.x - wideSep, y1: topY, x2: bar.x - wideSep, y2: bottomY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x,           y1: topY, x2: bar.x,           y2: bottomY,
                         stroke: "black", strokeWidth: thick)

        case .start:
            builder.line(x1: bar.x,            y1: topY, x2: bar.x,            y2: bottomY,
                         stroke: "black", strokeWidth: thick)
            builder.line(x1: bar.x + wideSep,  y1: topY, x2: bar.x + wideSep,  y2: bottomY,
                         stroke: "black", strokeWidth: thin)

        case .repeatEnd:
            // Right-anchored: thick bar at bar.x, thin bar and dots to its left.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: bottomY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: bottomY, stroke: "black", strokeWidth: thick)

        case .repeatStart:
            let thinX  = bar.x
            let thickX = thinX + wideSep
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: bottomY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: bottomY, stroke: "black", strokeWidth: thick)
            emitRepeatDots(isStartSide: true, nearX: thickX, topY: topY, bottomY: bottomY, builder: &builder)

        case .repeatBoth:
            // Right-anchored: thick bar at bar.x, thin bar to its left; start-repeat
            // dots extend rightward past bar.x into the next measure's left margin.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: bottomY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: bottomY, stroke: "black", strokeWidth: thick)
            emitRepeatDots(isStartSide: true, nearX: thickX, topY: topY, bottomY: bottomY, builder: &builder)

        case .sectionRepeatStart:
            let thickX = bar.x
            let thinX  = thickX + wideSep
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: bottomY, stroke: "black", strokeWidth: thick)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: bottomY, stroke: "black", strokeWidth: thin)
            emitRepeatDots(isStartSide: true, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)

        case .repeatEndSection:
            // Right-anchored: thick bar at bar.x, thin bar and dots to its left.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: bottomY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: bottomY, stroke: "black", strokeWidth: thick)
        }
    }

    /// Draws the two repeat dots (at the 2nd and 3rd staff spaces from the bottom).
    ///
    /// - Parameters:
    ///   - isStartSide: `true` places dots to the right of `nearX` (start-repeat);
    ///     `false` places them to the left (end-repeat).
    ///   - nearX: X of the bar line the dots abut.
    private func emitRepeatDots(isStartSide: Bool, nearX: Double,
                                 topY: Double, bottomY: Double, builder: inout SVGBuilder) {
        let staffSize = (bottomY - topY) / 4.0
        let fontSize  = 4.0 * staffSize
        let sep       = metadata.engravingDefaults.barlineSeparation * staffSize
        let dotW      = metadata.glyphBBoxes["repeatDot"].map { $0.width * staffSize } ?? staffSize * 0.25
        let dotX      = isStartSide ? nearX + sep * 1.0 : nearX - sep * 1.0 - dotW
        let dotChar   = String(SMuFLGlyph.repeatDot.character)
        builder.text(dotChar, x: dotX, y: bottomY - 1.5 * staffSize, fontFamily: "Bravura", fontSize: fontSize)
        builder.text(dotChar, x: dotX, y: bottomY - 2.5 * staffSize, fontFamily: "Bravura", fontSize: fontSize)
    }

    // MARK: - Events

    @discardableResult
    private func emitEvent(_ event: ResolvedEvent, topStaffY: Double, bottomStaffY: Double,
                           unitNoteLength: Fraction, precedingGraceBeamY: Double? = nil,
                           builder: inout SVGBuilder) -> StemInfo? {
        switch event.kind {
        case .note(let n):
            return emitNote(n, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                            unitNoteLength: unitNoteLength, precedingGraceBeamY: precedingGraceBeamY,
                            builder: &builder)
        case .rest(let r):
            emitRest(r, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                     unitNoteLength: unitNoteLength, builder: &builder)
        case .chord(let c):
            for note in c.notes {
                emitNote(note, x: event.origin.x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                         unitNoteLength: unitNoteLength, precedingGraceBeamY: precedingGraceBeamY,
                         builder: &builder)
            }
        case .grace:
            break // handled in emitMeasure to capture stem-tip Y
        case .tuplet, .spacer, .directiveAnchor:
            break // deferred to a future pass
        case .tempoChange(let t):
            let text = tempoAnnotationText(t)
            if !text.isEmpty {
                let fontSize = config.staffSize * 1.5
                builder.text(text, x: event.origin.x, y: topStaffY - config.staffSize * 1.5,
                             fontFamily: "Libertinus Serif", fontSize: fontSize)
            }
        }
        return nil
    }

    // MARK: - Notes

    @discardableResult
    private func emitNote(_ note: Note, x: Double, topStaffY: Double, bottomStaffY: Double,
                          unitNoteLength: Fraction, precedingGraceBeamY: Double? = nil,
                          builder: inout SVGBuilder) -> StemInfo? {
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

        if isDotted(absDur) {
            emitAugmentationDot(x: x, noteheadY: y, staffPos: staffPos, fontSize: fontSize,
                                builder: &builder)
        }

        emitDecorations(note.decorations, x: x, topStaffY: topStaffY, bottomStaffY: bottomStaffY,
                        fontSize: fontSize, precedingGraceBeamY: precedingGraceBeamY, builder: &builder)

        var stemInfo: StemInfo?
        if absDur < 1.0 {
            stemInfo = emitStem(staffPos: staffPos, noteheadY: y, x: x, absDur: absDur,
                                beamState: note.beam, builder: &builder)
        }

        emitLedgerLines(staffPos: staffPos, x: x, bottomStaffY: bottomStaffY, builder: &builder)
        return stemInfo
    }

    private func emitAugmentationDot(x: Double, noteheadY: Double, staffPos: Int,
                                      fontSize: Double, builder: inout SVGBuilder) {
        let noteW   = noteheadWidth()
        let dotGap  = noteW * 0.2
        let dotX    = x + noteW + dotGap

        // If the notehead sits on a line (even staffPos), shift dot up half a space to a space.
        let dotY = staffPos.isMultiple(of: 2)
            ? noteheadY - config.staffSize / 2.0
            : noteheadY
        builder.text(String(SMuFLGlyph.augmentationDot.character), x: dotX, y: dotY,
                     fontFamily: "Bravura", fontSize: fontSize)
    }

    private func isDotted(_ absDur: Double) -> Bool {
        // A dotted value has the form (2^n - 1) / 2^(n-1).  In practice: 3/4, 3/8, 3/16 …
        // Equivalently, when rounded to the nearest power of two, the "plain" duration differs.
        // Simple check: absDur * 4 is an integer of the form 4k+2 (i.e. odd when halved).
        // Handles 3/4 (dotted half), 3/8 (dotted quarter), 3/16 (dotted eighth), 3/32 (dotted 16th).
        let scaled = absDur * 64.0
        let rounded = Int(scaled.rounded())
        // A dotted note: numerator = 3 * 2^k for some k ≥ 0  →  rounded % 3 == 0 but not a plain 2^n.
        guard rounded > 0 else { return false }
        if (rounded & (rounded - 1)) == 0 { return false }  // plain power of two → not dotted
        return rounded % 3 == 0
    }

    @discardableResult
    private func emitStem(staffPos: Int, noteheadY: Double, x: Double, absDur: Double,
                           beamState: BeamState, builder: inout SVGBuilder) -> StemInfo {
        let stemUp: Bool
        switch stemDirection {
        case .up:   stemUp = true
        case .down: stemUp = false
        case .auto: stemUp = staffPos <= 4
        }
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

        // Only draw the stem immediately for unbeamed notes.
        // Beamed notes: emitBeamGroup draws stems at the correct common beam Y.
        if beamState == .single {
            builder.line(x1: stemX, y1: stemTop, x2: stemX, y2: stemBottom,
                         stroke: "black", strokeWidth: stemThick)
        }

        // Flags (only for un-beamed notes shorter than a quarter)
        if absDur < 0.25 && beamState == .single {
            let flagY = stemUp ? stemTop : stemBottom
            if config.straightFlags {
                emitStraightFlags(stemX: stemX, flagTipY: flagY, absDur: absDur, stemUp: stemUp,
                                  builder: &builder)
            } else {
                let fontSize = 4.0 * config.staffSize
                let flag     = flagGlyph(absDur: absDur, stemUp: stemUp)
                builder.text(String(flag.character), x: stemX, y: flagY,
                             fontFamily: "Bravura", fontSize: fontSize)
            }
        }

        return StemInfo(stemX: stemX, stemTipY: stemUp ? stemTop : stemBottom, stemUp: stemUp,
                        noteheadY: noteheadY)
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

    @discardableResult
    private func emitGraceGroup(_ grace: GraceGroup, originX: Double,
                                 topStaffY: Double, bottomStaffY: Double,
                                 builder: inout SVGBuilder) -> Double {
        guard !grace.notes.isEmpty else { return 0 }

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

            // Single grace note gets a 32nd-note flag (three flags); grace stems always point up.
            if !multiple {
                if config.straightFlags {
                    emitStraightFlags(stemX: pos.stemX, flagTipY: beamY, absDur: 0.03125,
                                      stemUp: true, scale: graceScale, builder: &builder)
                } else {
                    builder.text(String(SMuFLGlyph.flag32ndUp.character), x: pos.stemX, y: beamY,
                                 fontFamily: "Bravura", fontSize: fontSize)
                }
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

        return beamY
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

    // MARK: - Tie arc

    private func emitTieArc(fromX: Double, fromY: Double, staffPos: Int,
                             toX: Double, toY: Double, builder: inout SVGBuilder) {
        let s     = config.staffSize
        let noteW = noteheadWidth()
        let x1    = fromX + noteW   // right edge of the starting notehead
        let x2    = toX             // left edge of the ending notehead
        // Stems go up for staffPos ≤ 4; tie arcs go to the opposite side of the stem.
        let tieBelow  = staffPos <= 4
        let endOffset = tieBelow ? s : -s     // shift endpoints one staff line away from note centre
        let dy        = tieBelow ? s * 0.75 : -(s * 0.75)
        let span  = x2 - x1
        let cp1x  = x1 + span / 3.0
        let cp2x  = x2 - span / 3.0
        let y1    = fromY + endOffset
        let y2    = toY   + endOffset
        let d     = "M \(builder.fmt(x1)) \(builder.fmt(y1))" +
                    " C \(builder.fmt(cp1x)) \(builder.fmt(y1 + dy))" +
                    " \(builder.fmt(cp2x)) \(builder.fmt(y2 + dy))" +
                    " \(builder.fmt(x2)) \(builder.fmt(y2))"
        let strokeWidth = metadata.engravingDefaults.stemThickness * s * 1.5
        builder.path(d: d, fill: "none", stroke: "black", strokeWidth: strokeWidth)
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
        if absDur >= 0.125  { return stemUp ? .flag8thUp  : .flag8thDown  }
        if absDur >= 0.0625 { return stemUp ? .flag16thUp : .flag16thDown }
        return stemUp ? .flag32ndUp : .flag32ndDown
    }

    /// Draws straight flags as SVG lines using Bravura metadata proportions.
    /// Geometry (in staff spaces): flag width=0.96, first-flag height=1.42, spacing=0.80.
    private func emitStraightFlags(stemX: Double, flagTipY: Double, absDur: Double,
                                    stemUp: Bool, scale: Double = 1.0, builder: inout SVGBuilder) {
        let s         = config.staffSize * scale
        let flagCount = absDur >= 0.125 ? 1 : absDur >= 0.0625 ? 2 : 3
        let width     = 0.96 * s
        let height    = 1.42 * s
        let spacing   = 0.80 * s
        let thick     = metadata.engravingDefaults.stemThickness * s * 2.0

        for i in 0..<flagCount {
            let offset = Double(i) * spacing
            let y1 = stemUp ? flagTipY + offset         : flagTipY - offset
            let y2 = stemUp ? flagTipY + offset + height : flagTipY - offset - height
            builder.line(x1: stemX, y1: y1, x2: stemX + width, y2: y2,
                         stroke: "black", strokeWidth: thick)
        }
    }

    private func emitDecorations(_ decorations: [Decoration], x: Double,
                                  topStaffY: Double, bottomStaffY: Double,
                                  fontSize: Double, precedingGraceBeamY: Double? = nil,
                                  builder: inout SVGBuilder) {
        guard !decorations.isEmpty else { return }
        let s = config.staffSize
        // Center x over the notehead: offset from note origin to the glyph's horizontal midpoint.
        let nhBBox = metadata.glyphBBoxes["noteheadBlack"]
        let nhCenterX = ((nhBBox?.swX ?? 0.0) + (nhBBox?.neX ?? 1.18)) / 2.0 * s

        for decoration in decorations {
            switch decoration {
            case .fermata:
                let faBBox = metadata.glyphBBoxes["fermataAbove"]
                let faCenterX = ((faBBox?.swX ?? 0.012) + (faBBox?.neX ?? 2.42)) / 2.0 * s
                let fermataX = x + nhCenterX - faCenterX

                // Y: at least one staff space above the top line; pushed higher if a preceding
                // grace group's stem tip would be overlapped.
                let descent = abs(faBBox?.swY ?? 0.012) * s
                let gap = 0.5 * s
                var fermataY = topStaffY - s
                if let graceBeamY = precedingGraceBeamY {
                    fermataY = min(fermataY, graceBeamY - gap - descent)
                }
                builder.text(String(SMuFLGlyph.fermataAbove.character), x: fermataX, y: fermataY,
                             fontFamily: "Bravura", fontSize: fontSize)

            case .invertedFermata:
                let fbBBox = metadata.glyphBBoxes["fermataBelow"]
                let fbCenterX = ((fbBBox?.swX ?? 0.012) + (fbBBox?.neX ?? 2.42)) / 2.0 * s
                let fermataX = x + nhCenterX - fbCenterX
                let fermataY = bottomStaffY + s + fontSize * 0.25
                builder.text(String(SMuFLGlyph.fermataBelow.character), x: fermataX, y: fermataY,
                             fontFamily: "Bravura", fontSize: fontSize)

            default:
                break
            }
        }
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
