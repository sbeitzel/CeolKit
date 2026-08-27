import CeolKitModel
import Foundation

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
    let x: Double       // left-edge x of the notehead where the tie originates (or a staff edge, see below)
    let noteY: Double   // y of the notehead
    let pitch: Pitch    // matched against the end note's pitch
    let staffPos: Int   // determines whether the arc curves above or below the note
    // True once this anchor has been carried across a system/page break: `x` then refers
    // to the left staff edge of the new system rather than a real notehead, so the arc
    // drawn to resolve it must not add notehead-width clearance on that side (see #27).
    var isCarriedOver: Bool = false
}

/// Pending slur: records the start position of an open slur bracket so the arc
/// can be drawn when the matching closing `)` note is encountered.  Stored as a
/// LIFO stack so that nested slurs resolve correctly (innermost closes first).
private struct SlurAnchor {
    let x: Double       // left-edge x of the notehead where the slur opens (or a staff edge, see below)
    let noteY: Double   // y of the notehead
    let staffPos: Int   // determines whether the arc curves above or below
    var isCarriedOver: Bool = false  // see TieAnchor.isCarriedOver
}

// MARK: - Pass 5

/// Pass 5: converts a `ResolvedLayout` into one self-contained SVG document per page.
///
/// How self-contained depends on `config.textRendering`: the default writes the glyph
/// geometry into the document, which needs no font environment at all, while `.fontFace`
/// embeds each face as a base64 `@font-face` source, which browsers honour and no other
/// rasteriser does. See ``TextRendering``.
struct SVGEmitter: Sendable {
    let config: SVGRenderConfig
    let metadata: BravuraMetadata
    let stemDirection: StemDirection
    let accidentalMetrics: AccidentalMetrics

    init(config: SVGRenderConfig, metadata: BravuraMetadata, stemDirection: StemDirection = .auto) {
        self.config = config
        self.metadata = metadata
        self.stemDirection = stemDirection
        self.accidentalMetrics = AccidentalMetrics(config: config, metadata: metadata)
    }

    // MARK: - Public entry point

    func emit(_ layout: ResolvedLayout) throws -> [String] {
        // Each is skipped when the mode does not need it: reading and base64-encoding three
        // OTFs is the emitter's most expensive step, and parsing them for outlines is not
        // free either.
        let embeddedFaces = config.textRendering.embedsFontFaces
            ? EmbeddedFaces(
                bravura: try CeolKitFonts.base64(for: .bravura),
                libertinusSerif: try LibertinusSerifMetrics.loadBase64(),
                libertinusSerifItalic: try LibertinusSerifMetrics.loadItalicBase64())
            : nil
        let fonts = config.textRendering.emitsOutlines ? try OutlineFontSet.shared() : nil
        // Threaded across every page/system so ties and slurs that span a system or page
        // break (#27) are resolved with dangling arcs instead of being silently dropped.
        var pendingTies:  [TieAnchor]  = []
        var pendingSlurs: [SlurAnchor] = []
        var documents: [String] = []
        documents.reserveCapacity(layout.pages.count)
        for (pageIndex, page) in layout.pages.enumerated() {
            let document = emitPage(page, pageNumber: pageIndex + 1, layout: layout,
                                     embeddedFaces: embeddedFaces, fonts: fonts,
                                     pendingTies: &pendingTies, pendingSlurs: &pendingSlurs)
            documents.append(document)
        }
        return documents
    }

    // MARK: - Page

    private func emitPage(_ page: ResolvedPage, pageNumber: Int, layout: ResolvedLayout,
                           embeddedFaces: EmbeddedFaces?, fonts: OutlineFontSet?,
                           pendingTies: inout [TieAnchor], pendingSlurs: inout [SlurAnchor]) -> String {
        var builder = SVGBuilder(textRendering: config.textRendering, fonts: fonts)
        emitScrollSyncMetadata(for: page, pageNumber: pageNumber, builder: &builder)
        emitTitleBlock(page.titleRows, builder: &builder)
        for system in page.systems {
            // Systems on one page can come from tunes with different %%ceolkit:scale factors
            // and grace spacings, so each is emitted through a copy of self configured for
            // that system.
            configured(for: system)
                .emitSystem(system, pendingTies: &pendingTies, pendingSlurs: &pendingSlurs,
                            builder: &builder)
        }
        emitFooterBlock(page.footerRows, builder: &builder)
        return builder.buildDocument(
            width: layout.pageSize.width,
            height: layout.pageSize.height,
            embeddedFaces: embeddedFaces
        )
    }

    /// Returns a copy of this emitter carrying `system`'s own per-tune config values.
    ///
    /// Every staff, glyph, stem, and beam dimension below `emitSystem` is expressed as a
    /// multiple of `config.staffSize`, so swapping it here scales an entire system without
    /// threading a size argument through the whole emission tree.  `graceNoteSpacing` rides
    /// along for a different reason: the sizer reserved this system's grace groups with it,
    /// and a group drawn at any other step would not fill the space it was given.
    private func configured(for system: ResolvedSystem) -> SVGEmitter {
        guard system.staffSize != config.staffSize
                || system.graceNoteSpacing != config.graceNoteSpacing else { return self }
        var systemConfig = config
        systemConfig.staffSize = system.staffSize
        systemConfig.graceNoteSpacing = system.graceNoteSpacing
        return SVGEmitter(config: systemConfig, metadata: metadata, stemDirection: stemDirection)
    }

    // MARK: - Scroll-sync metadata

    /// Emits the `ceolkit-meta` comment (issue #25) listing each staff system's
    /// originating ABC source line and page Y coordinate, so editor consumers
    /// (e.g. ScoreEdit) can synchronise scroll position with the source.
    ///
    /// One anchor per staff drawn, including each staff of a multi-voice system — the
    /// geometry reader pairs anchors with staves positionally, so the two counts have to
    /// match.  The staves of a system all carry the system's line, which leaves the
    /// sequence monotonic: a consumer keeping only strictly increasing anchors (#41) ends
    /// up with exactly the top staff of each system, which is the one it wants.
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

    private func emitSystem(_ system: ResolvedSystem,
                             pendingTies: inout [TieAnchor], pendingSlurs: inout [SlurAnchor],
                             builder: inout SVGBuilder) {
        emitStaffLines(system, builder: &builder)
        emitStaffGroupConnector(system, builder: &builder)
        emitClef(system, builder: &builder)
        if let keySig = system.keySignature {
            emitKeySignature(keySig, system: system, builder: &builder)
        }
        if let meter = system.meter {
            emitTimeSignature(meter, system: system, builder: &builder)
        }

        // Anchors still open from the previous system/page (#27) are dangling ties/slurs.
        // Re-anchor them to this system's left staff edge so the closing logic in
        // emitMeasure draws an "arriving" arc when the matching note is found.
        let leftEdge = system.origin.x
        pendingTies = pendingTies.map {
            TieAnchor(x: leftEdge, noteY: $0.noteY, pitch: $0.pitch, staffPos: $0.staffPos, isCarriedOver: true)
        }
        pendingSlurs = pendingSlurs.map {
            SlurAnchor(x: leftEdge, noteY: $0.noteY, staffPos: $0.staffPos, isCarriedOver: true)
        }

        for measure in system.measures {
            emitMeasure(measure, system: system,
                        pendingTies: &pendingTies, pendingSlurs: &pendingSlurs,
                        builder: &builder)
        }

        // Anchors still open at the end of this system span into the next system/page.
        // Draw a departing dangling arc to the right staff edge; the anchor itself is left
        // in place (still holding pitch/staffPos) so the next emitSystem call can resolve
        // or re-dangle it in turn.
        if let lastMeasure = system.measures.last {
            let rightEdge = lastMeasure.origin.x + lastMeasure.width
            for anchor in pendingTies {
                emitDanglingArc(fromX: anchor.x, y: anchor.noteY, staffPos: anchor.staffPos,
                                toEdgeX: rightEdge, isCarriedOver: anchor.isCarriedOver,
                                kind: .tie, builder: &builder)
            }
            for anchor in pendingSlurs {
                emitDanglingArc(fromX: anchor.x, y: anchor.noteY, staffPos: anchor.staffPos,
                                toEdgeX: rightEdge, isCarriedOver: anchor.isCarriedOver,
                                kind: .slur, builder: &builder)
            }
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

    /// The furniture at the left edge of a multi-voice system: the rule that joins its
    /// staves, and the brace or bracket over each span the tune's `%%score`/`%%staves`
    /// plan states.
    ///
    /// Without the rule the staves of a system are just neighbouring staves; with it they
    /// read as one system, which is what tells a player that the parts are to be followed
    /// together.  It is drawn once per group, by its top staff, and at the staff lines' own
    /// weight rather than a barline's: it is a continuation of the staff furniture, so that
    /// is what it should look like — and it is what lets `CeolKitSVGGeometry` tell it apart
    /// from the barlines it sits alongside, which are thicker.
    ///
    /// The spans are drawn each by the staff it starts at, which is where
    /// `VerticalLayoutEngine` anchored it, so a span opening below the group's top staff is
    /// drawn by that staff and not by the leader.
    private func emitStaffGroupConnector(_ system: ResolvedSystem, builder: inout SVGBuilder) {
        guard let group = system.staffGroup else { return }
        if group.isGroupLeader {
            let topY = system.origin.y + system.staffOrigin
            let thickness = metadata.engravingDefaults.staffLineThickness * config.staffSize
            builder.line(x1: system.origin.x, y1: topY, x2: system.origin.x, y2: group.bottomY,
                         stroke: "black", strokeWidth: thickness)
        }
        for span in group.spans { emitStaffSpan(span, builder: &builder) }
    }

    /// One brace or bracket, standing in the indent reserved for its depth.
    private func emitStaffSpan(_ span: StaffGroup.Span, builder: inout SVGBuilder) {
        switch span.bracket {
        case .brace:   emitStaffSpanBrace(span, builder: &builder)
        case .bracket: emitStaffSpanBracket(span, builder: &builder)
        }
    }

    /// The brace over a `{ … }` span, stretched from the first staff's top line to the
    /// last's bottom one.
    ///
    /// SMuFL's brace is a *stretchy* glyph: the face draws it 3.988 staff spaces tall, a
    /// third of what two staves of a piano system span, so it is never drawn at its natural
    /// size.  The two axes move independently — see ``BracketColumns/braceScale(height:metadata:staffSize:)``
    /// for how far the arms are allowed to thicken as the span grows.
    ///
    /// A nested brace is drawn exactly like an outer one.  Unlike the bracket it has no
    /// thinner form to fall back to, and it needs none: it stands in its own column, so the
    /// nesting is legible from where it sits.
    private func emitStaffSpanBrace(_ span: StaffGroup.Span, builder: inout SVGBuilder) {
        let s = config.staffSize
        guard let scale = BracketColumns.braceScale(height: span.bottomY - span.topY,
                                                    metadata: metadata, staffSize: s)
        else { return }
        // The glyph stands on its baseline — Bravura's `bBoxSW.y` is 0 — but read the offset
        // rather than assume it, and stretch it along with everything else, so the brace's
        // foot lands on the bottom staff line and not near it.
        let footOffset = (metadata.glyphBBoxes["brace"]?.swY ?? 0) * s * scale.y
        builder.stretchedText(String(SMuFLGlyph.brace.character),
                              x: span.x, y: span.bottomY + footOffset,
                              fontFamily: "Bravura", fontSize: 4.0 * s,
                              xScale: scale.x, yScale: scale.y)
    }

    /// The bracket over a `[ … ]` span: a spine at `bracketThickness` with the face's
    /// flared tips at its ends.
    ///
    /// A nested span is drawn at `subBracketThickness` with short hooks in place of those
    /// tips: SMuFL publishes no sub-bracket glyph, a sub-bracket being a thin spine serifed
    /// at each end.
    private func emitStaffSpanBracket(_ span: StaffGroup.Span, builder: inout SVGBuilder) {
        let s = config.staffSize
        let defaults = metadata.engravingDefaults
        let isNested = span.depth > 0
        let thickness = (isNested ? defaults.subBracketThickness : defaults.bracketThickness) * s
        // `span.x` is the spine's left edge; a stroke is drawn centred on its x.
        let spineX = span.x + thickness / 2
        builder.line(x1: spineX, y1: span.topY, x2: spineX, y2: span.bottomY,
                     stroke: "black", strokeWidth: thickness)

        guard isNested else {
            let fontSize = 4.0 * s
            builder.text(String(SMuFLGlyph.bracketTop.character), x: span.x, y: span.topY,
                         fontFamily: "Bravura", fontSize: fontSize)
            builder.text(String(SMuFLGlyph.bracketBottom.character), x: span.x, y: span.bottomY,
                         fontFamily: "Bravura", fontSize: fontSize)
            return
        }
        // Inset by half the spine's weight so the hooks stay inside the span rather than
        // overhanging the staff lines they terminate on.
        let hookEndX = span.x + BracketColumns.subBracketHookLength(staffSize: s)
        for y in [span.topY + thickness / 2, span.bottomY - thickness / 2] {
            builder.line(x1: spineX, y1: y, x2: hookEndX, y2: y,
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
        // Where the boundary below this staff is joined, the bar lines run on down to the
        // next staff's top line, so the joined staves' bar lines read as one stroke.  §11.1
        // makes that a property of the boundary — `|` in `%%score` — and with no plan every
        // boundary is joined, so a multi-voice system without one is drawn as it always was.
        // Repeat dots still belong to the staff that owns them, so they keep `bottomY`.
        let group = system.staffGroup
        let lineBottomY = (group?.continuesBarlineBelow ?? false)
            ? (group?.nextStaffTopY ?? bottomY)
            : bottomY

        if let opening = measure.openingBar {
            emitBarLine(opening, topY: topY, bottomY: bottomY, lineBottomY: lineBottomY, builder: &builder)
        }
        emitBarLine(measure.closingBar, topY: topY, bottomY: bottomY,
                    lineBottomY: lineBottomY, builder: &builder)

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
                        if anchor.isCarriedOver {
                            emitArrivingTieArc(edgeX: anchor.x, staffPos: anchor.staffPos,
                                               toX: event.origin.x, toY: ny,
                                               kind: .tie, builder: &builder)
                        } else {
                            emitTieArc(fromX: anchor.x, fromY: anchor.noteY, staffPos: anchor.staffPos,
                                       toX: event.origin.x, toY: ny, kind: .tie, builder: &builder)
                        }
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
                        if anchor.isCarriedOver {
                            emitArrivingTieArc(edgeX: anchor.x, staffPos: anchor.staffPos,
                                               toX: event.origin.x, toY: ny,
                                               kind: .slur, builder: &builder)
                        } else {
                            emitTieArc(fromX: anchor.x, fromY: anchor.noteY, staffPos: anchor.staffPos,
                                       toX: event.origin.x, toY: ny, kind: .slur, builder: &builder)
                        }
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

    /// Draws one bar line.
    ///
    /// - Parameters:
    ///   - topY: Y of this staff's top line.
    ///   - bottomY: Y of this staff's bottom line.  Sizes the staff-relative furniture —
    ///     the repeat dots, which always sit inside the staff that owns them.
    ///   - lineBottomY: How far down the vertical strokes actually run.  Equal to `bottomY`
    ///     on a single staff and on the last staff of a system; on any other staff of a
    ///     multi-voice system it is the *next* staff's top line, so the bar line carries
    ///     through the gap and the system's bar lines read as one stroke.
    private func emitBarLine(_ bar: ResolvedBarLine, topY: Double, bottomY: Double,
                              lineBottomY: Double? = nil, builder: inout SVGBuilder) {
        let thin    = metadata.engravingDefaults.thinBarlineThickness  * config.staffSize
        let thick   = metadata.engravingDefaults.thickBarlineThickness * config.staffSize
        let sep     = metadata.engravingDefaults.barlineSeparation     * config.staffSize
        let wideSep = sep * 2.0
        let footY   = lineBottomY ?? bottomY

        switch bar.kind {
        case .single, .dotted:
            builder.line(x1: bar.x, y1: topY, x2: bar.x, y2: footY,
                         stroke: "black", strokeWidth: thin)

        case .double:
            // Right-anchored: trailing thin bar at bar.x, leading thin bar to its left,
            // so the pair ends where the staff lines end at a system break.
            builder.line(x1: bar.x - sep, y1: topY, x2: bar.x - sep, y2: footY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x,       y1: topY, x2: bar.x,       y2: footY,
                         stroke: "black", strokeWidth: thin)

        case .final:
            // Right-anchored: thick bar trailing edge at bar.x, thin bar to its left.
            builder.line(x1: bar.x - wideSep, y1: topY, x2: bar.x - wideSep, y2: footY,
                         stroke: "black", strokeWidth: thin)
            builder.line(x1: bar.x,           y1: topY, x2: bar.x,           y2: footY,
                         stroke: "black", strokeWidth: thick)

        case .start:
            builder.line(x1: bar.x,            y1: topY, x2: bar.x,            y2: footY,
                         stroke: "black", strokeWidth: thick)
            builder.line(x1: bar.x + wideSep,  y1: topY, x2: bar.x + wideSep,  y2: footY,
                         stroke: "black", strokeWidth: thin)

        case .repeatEnd:
            // Right-anchored: thick bar at bar.x, thin bar and dots to its left.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: footY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: footY, stroke: "black", strokeWidth: thick)

        case .repeatStart:
            let thinX  = bar.x
            let thickX = thinX + wideSep
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: footY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: footY, stroke: "black", strokeWidth: thick)
            emitRepeatDots(isStartSide: true, nearX: thickX, topY: topY, bottomY: bottomY, builder: &builder)

        case .repeatBoth:
            // Right-anchored: thick bar at bar.x, thin bar to its left; start-repeat
            // dots extend rightward past bar.x into the next measure's left margin.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: footY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: footY, stroke: "black", strokeWidth: thick)
            emitRepeatDots(isStartSide: true, nearX: thickX, topY: topY, bottomY: bottomY, builder: &builder)

        case .sectionRepeatStart:
            let thickX = bar.x
            let thinX  = thickX + wideSep
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: footY, stroke: "black", strokeWidth: thick)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: footY, stroke: "black", strokeWidth: thin)
            emitRepeatDots(isStartSide: true, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)

        case .repeatEndSection:
            // Right-anchored: thick bar at bar.x, thin bar and dots to its left.
            let thickX = bar.x
            let thinX  = thickX - wideSep
            emitRepeatDots(isStartSide: false, nearX: thinX, topY: topY, bottomY: bottomY, builder: &builder)
            builder.line(x1: thinX,  y1: topY, x2: thinX,  y2: footY, stroke: "black", strokeWidth: thin)
            builder.line(x1: thickX, y1: topY, x2: thickX, y2: footY, stroke: "black", strokeWidth: thick)
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
        // SMuFL sizes this gap specifically — it is not the generic barlineSeparation, and at
        // Bravura's values the two differ by more than a factor of two (0.16 vs 0.4).
        let sep       = metadata.engravingDefaults.repeatBarlineDotSeparation * staffSize
        let dotW      = metadata.glyphBBoxes["repeatDot"].map { $0.width * staffSize } ?? staffSize * 0.25
        let dotX      = isStartSide ? nearX + sep : nearX - sep - dotW
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

    /// Draws an accidental left of the notehead at `x`.
    ///
    /// The offset is the glyph's own width plus a clearance gap — a fixed offset would let
    /// the wider glyphs (a double flat is 1.644 staff spaces) run over the notehead.
    private func emitAccidental(_ alt: Alteration, x: Double, y: Double,
                                fontSize: Double, scale: Double = 1.0,
                                builder: inout SVGBuilder) {
        guard let glyph = SMuFLGlyph.accidental(for: alt) else { return }
        let offset = accidentalMetrics.offset(for: alt, scale: scale)
        builder.text(String(glyph.character), x: x - offset, y: y,
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
    private var graceScale: Double { GraceMetrics.scale }

    @discardableResult
    private func emitGraceGroup(_ grace: GraceGroup, originX: Double,
                                 topStaffY: Double, bottomStaffY: Double,
                                 builder: inout SVGBuilder) -> Double {
        guard !grace.notes.isEmpty else { return 0 }

        let s          = config.staffSize
        let fontSize   = 4.0 * s * graceScale
        let stemThick  = metadata.engravingDefaults.stemThickness * s
        let metrics    = GraceMetrics(config: config, metadata: metadata)
        let stemLength = 3.5 * s * graceScale
        let multiple   = grace.notes.count > 1

        // Pre-pass: compute notehead Y and stem X for each grace note.
        // Notehead x positions come from `GraceMetrics`, the same source the sizer used to
        // reserve this group's width.
        struct GracePos { let x, noteheadY, stemX: Double; let staffPos: Int }
        let noteheadXs = metrics.noteheadOffsets(grace.notes)
        let positions: [GracePos] = grace.notes.enumerated().map { i, note in
            let x   = originX + noteheadXs[i]
            let sp  = self.staffPos(for: note.pitch)
            let y   = noteY(staffPos: sp, bottomStaffY: bottomStaffY)
            return GracePos(x: x, noteheadY: y, stemX: x + metrics.noteheadWidth, staffPos: sp)
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

            if let acc = note.displayedAccidental {
                emitAccidental(acc, x: pos.x, y: pos.noteheadY, fontSize: fontSize,
                               scale: graceScale, builder: &builder)
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

    /// Which of the two curved marks is being drawn. They are geometrically identical and
    /// differ only in which pair of SMuFL thicknesses governs the taper — a distinction
    /// Bravura happens to collapse (0.1/0.22 for both) but other faces need not.
    private enum ArcKind {
        case tie
        case slur

        func thicknesses(_ ed: BravuraMetadata.EngravingDefaults) -> (endpoint: Double, midpoint: Double) {
            switch self {
            case .tie:  return (ed.tieEndpointThickness,  ed.tieMidpointThickness)
            case .slur: return (ed.slurEndpointThickness, ed.slurMidpointThickness)
            }
        }
    }

    /// Draws the cubic-bezier arc shared by ties and slurs, given final endpoint x's and
    /// each endpoint's un-offset (notehead-centre) y. Stems go up for staffPos ≤ 4; arcs
    /// curve to the opposite side of the stem.
    ///
    /// SMuFL specifies the mark as *tapered* — thin at the endpoints, thick at the middle —
    /// which a single stroked curve cannot express whatever width it picks. So the arc is a
    /// closed outline: the centre-line curve offset outward, then the same curve offset
    /// inward and traversed backwards, filled rather than stroked.
    private func emitArc(x1: Double, rawY1: Double, x2: Double, rawY2: Double, staffPos: Int,
                          kind: ArcKind, builder: inout SVGBuilder) {
        let s = config.staffSize
        let tieBelow  = staffPos <= 4
        let endOffset = tieBelow ? s : -s     // shift endpoints one staff line away from note centre
        let dy        = tieBelow ? s * 0.75 : -(s * 0.75)
        let span = x2 - x1
        let cp1x = x1 + span / 3.0
        let cp2x = x2 - span / 3.0
        let y1   = rawY1 + endOffset
        let y2   = rawY2 + endOffset

        // Half-widths of the ribbon, measured either side of the centre line. Subtracting one
        // boundary curve from the other leaves a third cubic — the thickness along the arc —
        // which at t = 0.5 measures (halfEnd + 3·halfInner)/2. Setting that equal to the
        // midpoint thickness gives how far the interior control points have to move.
        let (endThick, midThick) = kind.thicknesses(metadata.engravingDefaults)
        let halfEnd   = endThick * s / 2.0
        let halfInner = (4.0 * midThick - endThick) * s / 6.0

        /// One boundary of the ribbon: the centre line with its control points displaced by
        /// `sign · halfInner` and its endpoints by `sign · halfEnd`. The shape is symmetric
        /// about the centre line, so which sign lands on the outside of the bulge does not
        /// matter — only that the two boundaries take opposite signs.
        func boundary(_ sign: Double, reversed: Bool) -> String {
            let c1 = builder.fmt(y1 + dy + sign * halfInner)
            let c2 = builder.fmt(y2 + dy + sign * halfInner)
            return reversed
                ? " C \(builder.fmt(cp2x)) \(c2) \(builder.fmt(cp1x)) \(c1)" +
                  " \(builder.fmt(x1)) \(builder.fmt(y1 + sign * halfEnd))"
                : " C \(builder.fmt(cp1x)) \(c1) \(builder.fmt(cp2x)) \(c2)" +
                  " \(builder.fmt(x2)) \(builder.fmt(y2 + sign * halfEnd))"
        }
        let d = "M \(builder.fmt(x1)) \(builder.fmt(y1 + halfEnd))" +
                boundary(1, reversed: false) +
                " L \(builder.fmt(x2)) \(builder.fmt(y2 - halfEnd))" +
                boundary(-1, reversed: true) +
                " Z"
        builder.path(d: d, fill: "black", stroke: "none")
    }

    /// Note-to-note tie/slur arc: the start point clears the starting notehead's width,
    /// the end point sits at the ending notehead's left edge.
    private func emitTieArc(fromX: Double, fromY: Double, staffPos: Int,
                             toX: Double, toY: Double, kind: ArcKind, builder: inout SVGBuilder) {
        emitArc(x1: fromX + noteheadWidth(), rawY1: fromY, x2: toX, rawY2: toY,
               staffPos: staffPos, kind: kind, builder: &builder)
    }

    /// Arriving arc for a tie/slur carried over from a previous system (#27): starts
    /// exactly at the staff's left edge (no notehead clearance, since there's no note
    /// there) and curves in to the resolving note.
    private func emitArrivingTieArc(edgeX: Double, staffPos: Int,
                                     toX: Double, toY: Double, kind: ArcKind,
                                     builder: inout SVGBuilder) {
        emitArc(x1: edgeX, rawY1: toY, x2: toX, rawY2: toY, staffPos: staffPos,
                kind: kind, builder: &builder)
    }

    /// Departing dangling arc for a tie/slur still open at the end of a system (#27):
    /// curves from the anchor out to the staff's right edge (open-ended). If the anchor
    /// itself was already carried in from a previous system (never resolved within this
    /// one), both ends are open edges and neither gets notehead-width clearance.
    private func emitDanglingArc(fromX: Double, y: Double, staffPos: Int, toEdgeX: Double,
                                  isCarriedOver: Bool, kind: ArcKind, builder: inout SVGBuilder) {
        if isCarriedOver {
            emitArc(x1: fromX, rawY1: y, x2: toEdgeX, rawY2: y, staffPos: staffPos,
                    kind: kind, builder: &builder)
        } else {
            emitTieArc(fromX: fromX, fromY: y, staffPos: staffPos, toX: toEdgeX, toY: y,
                       kind: kind, builder: &builder)
        }
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
    ///
    /// The stroke width is a multiple of `stemThickness` rather than a published value:
    /// SMuFL's `engravingDefaults` has no key for flag thickness, since a conforming face
    /// supplies flags as glyphs and never expects them to be constructed.
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

    private func noteheadWidth() -> Double {
        metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
            ?? config.staffSize * 1.2
    }
}
