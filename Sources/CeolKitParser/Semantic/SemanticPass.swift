import Foundation
import CeolKitModel

/// Converts the syntactic ABCFile into the public Score domain model.
struct SemanticPass {
    let file: ABCFile
    let options: ParseOptions
    let dialectHint: Dialect?

    func build() -> (Score, [Diagnostic]) {
        var diagnostics = file.diagnostics

        // Process file-preamble directives: collect ceolkit directives to promote to first tune.
        // filePreamble contains both the initial preamble and any inter-tune gaps (lines between
        // tunes that fall outside any tune header), so scanning it here covers both.
        var preambleCeolKitDirectives: [CeolKitDirectiveScope] = []
        // `%%newpage` met outside any tune, in source order.  Unlike everything else in the
        // preamble these are *not* promoted to the first tune: a break written in the gap
        // between two tunes belongs to the one that follows it, so each is matched to its
        // tune by source line in the walk below.
        var preambleBreaks: [PageBreak] = []
        // Every `%%footer` met outside a tune, in source order, each with the line it was
        // written on.  `filePreamble` holds the file header *and* the gaps between tunes, and
        // the two mean different things: a footer in the file header governs the whole file
        // (ABC v2.2 §4.23), one written in a gap governs the tunes that follow it.  Keeping
        // the lines is what lets the walk below tell them apart (issue #155).
        var outsideFooters: [(template: String, line: Int)] = []
        // Every `%%score` / `%%staves` met outside a tune, in source order, each with the line
        // it was written on.  A plan governs from where it stands: one in the file header
        // governs every tune (ABC v2.2 §4.23), one written in the gap between two tunes
        // governs the tunes that follow it and not the ones before, exactly as `%%footer`
        // does (issue #157).  Unlike a footer a plan names *voices*, so whether it applies to
        // a given tune is decided per tune in the walk below.
        var outsidePlans: [(plan: StaffPlan, line: Int)] = []
        // Every `%%landscape` met in the gap *between* tunes, in source order.  Unlike the
        // rest of the preamble these are not promoted to the first tune: a page size cannot
        // change part-way down a page, so a change of orientation is a property of the break
        // it is written at, and one written in a gap belongs to the tune that follows it —
        // never to the tunes before, which is what made a late `%%landscape` reorient pages
        // already engraved (issue #158).  A `%%landscape` in the *file header*, ahead of every
        // tune, is not a change but the orientation the document opens in, and is promoted as
        // it always was.
        var outsideOrientations: [OrientationRequest] = []
        // The line the music starts on, which is what separates the file header from the gaps
        // between tunes.  Needed while the preamble is being walked, so it is worked out here
        // rather than with the other per-tune values below.
        let firstTuneLine = file.tunes.first?.source.line ?? Int.max
        let preambleDirectives = file.filePreamble.compactMap { line -> StylesheetDirective? in
            switch line {
            case .directive(let name, let payload, let src):
                return (name: name, payload: payload, source: src)
            case .informationField(let code, let payload, let src) where code == "I":
                // §3.1.19: `I:name payload` in the file header is `%%name payload` there.
                guard case .instruction(let text) = parseField(code: code, payload: payload, source: src).0
                else { return nil }
                return stylesheetDirective(fromInstruction: text)
            default:
                return nil
            }
        }
        for (name, payload, src) in preambleDirectives {
            if name == "footer" {
                let footer = stripQuotes(payload.trimmingCharacters(in: .whitespaces))
                diagnoseFooterPlaceholders(footer, source: src, into: &diagnostics)
                outsideFooters.append((template: footer, line: src.line))
            } else if name == "newpage" {
                preambleBreaks.append(PageBreak(
                    beforeStave: 0,
                    restartingAt: parseNewPage(payload, source: src, diagnostics: &diagnostics),
                    source: src))
            } else if isCeolKitDirective(name) || isStandardDirective(name) {
                var tempDiags: [Diagnostic] = []
                if let d = parseCeolKitDirective(name: name, payload: payload, source: src, diagnostics: &tempDiags) {
                    if case .landscape(let on) = d, src.line > firstTuneLine {
                        // Written in a gap between tunes: a change of orientation, matched to
                        // the break in front of the tune that follows it (issue #158).
                        outsideOrientations.append(
                            OrientationRequest(landscape: on, stave: 0, source: src))
                    } else {
                        preambleCeolKitDirectives.append(
                            CeolKitDirectiveScope(directive: d, scope: .fileGlobal, source: src)
                        )
                    }
                    if case .staffPlan(let plan) = d {
                        outsidePlans.append((plan: plan, line: src.line))
                    }
                }
                diagnostics += tempDiags
            } else {
                diagnostics.append(Diagnostic(
                    severity: .info,
                    code: .unknownDirective,
                    message: "Unsupported stylesheet directive '%%\(name)'",
                    source: src
                ))
            }
        }

        let dialect: Dialect
        if let override = options.dialectOverride {
            dialect = override
        } else if let v = file.versionLine {
            dialect = .strict(version: v)
        } else {
            dialect = dialectHint ?? .loose
        }

        let fileSource = file.tunes.first?.source ?? .emptySourceRange

        // The footer the *file header* states: the last one written before any tune began.
        // A file with no tunes has nothing but a file header, so every one of them counts.
        let fileFooter = outsideFooters.last { $0.line < firstTuneLine }?.template

        var tunes: [Tune] = []
        var previousTuneLine = Int.min
        for (idx, abcTune) in file.tunes.enumerated() {
            let tuneLine = abcTune.source.line
            // What governs this tune: its own header's `%%footer` if it states one — a tune
            // header applies to its own tune and no other (ABC v2.2 §4.23, issue #155) —
            // otherwise the last one written outside a tune ahead of it.  `nil` where neither
            // exists, which leaves `Score.footer` standing for this tune.
            var tuneFooter = outsideFooters.last { $0.line < tuneLine }?.template
            for (name, payload, src) in abcTune.headerDirectives where name == "footer" {
                let footer = stripQuotes(payload.trimmingCharacters(in: .whitespaces))
                diagnoseFooterPlaceholders(footer, source: src, into: &diagnostics)
                tuneFooter = footer
            }
            // The preamble breaks standing between the previous tune and this one: they move
            // *this* tune onto a fresh page, so they are its own, at stave 0.
            let ownedBreaks = preambleBreaks.filter {
                $0.source.line > previousTuneLine && $0.source.line < tuneLine
            }
            let (tune, tuneDiags, tuneOrientations) = buildTune(abcTune, dialect: dialect)
            diagnostics += tuneDiags
            // Every `%%landscape` this tune can be asked to honour, in source order: the ones
            // written in the gap in front of it — which break before its first stave, exactly
            // as the `%%newpage` there does — then its own header's and body's.
            let gapOrientations = outsideOrientations.filter {
                $0.source.line > previousTuneLine && $0.source.line < tuneLine
            }
            previousTuneLine = tuneLine
            let breaks = resolvingOrientations(gapOrientations + tuneOrientations,
                                               against: ownedBreaks + tune.pageBreaks,
                                               into: &diagnostics)
            let extraDirectives = idx == 0 ? preambleCeolKitDirectives : []
            let filePlans = fileStaffPlans(
                for: tune,
                from: outsidePlans.last { $0.line < tuneLine }?.plan,
                into: &diagnostics)
            if !extraDirectives.isEmpty || breaks != tune.pageBreaks || tuneFooter != nil
                || !filePlans.isEmpty {
                tunes.append(Tune(
                    reference: tune.reference,
                    titles: tune.titles,
                    metadata: tune.metadata,
                    key: tune.key,
                    meter: tune.meter,
                    unitNoteLength: tune.unitNoteLength,
                    tempo: tune.tempo,
                    parts: tune.parts,
                    voices: tune.voices,
                    userSymbols: tune.userSymbols,
                    macros: tune.macros,
                    directives: extraDirectives + tune.directives,
                    staffPlans: filePlans + tune.staffPlans,
                    pageBreaks: breaks,
                    footer: tuneFooter,
                    source: tune.source
                ))
            } else {
                tunes.append(tune)
            }
        }

        // A `%%newpage` past the last tune has nothing left to move onto a fresh page.
        for orphan in preambleBreaks where orphan.source.line > previousTuneLine {
            diagnostics.append(Diagnostic(
                severity: .info, code: .pageBreakAfterLastTune,
                message: "%%newpage after the last tune has nothing to break before; ignored",
                source: orphan.source
            ))
        }

        // Nor has a `%%landscape` past the last tune a page left to turn.
        for orphan in outsideOrientations where orphan.source.line > previousTuneLine {
            diagnostics.append(Diagnostic(
                severity: .warning, code: .landscapeWithoutPageBreak,
                message: "%%landscape after the last tune has no page left to reorient; ignored",
                source: orphan.source
            ))
        }

        // Redundancy: %%flatbeams true is implied by %%ceolkit:pipeformat true.
        // Walk directives in source order; only flag %%flatbeams true that appears
        // after %%ceolkit:pipeformat true (a later %%flatbeams false is a valid override,
        // not redundant, because it actively changes the effective state).
        for tune in tunes {
            var pipeFormatActive = false
            for scope in tune.directives {
                switch scope.directive {
                case .pipeFormat(let on):
                    pipeFormatActive = on
                case .flatBeams(true) where pipeFormatActive:
                    diagnostics.append(Diagnostic(
                        severity: .info, code: .redundantDirective,
                        message: "%%flatbeams true is redundant when %%ceolkit:pipeformat is active",
                        source: scope.source
                    ))
                default:
                    break
                }
            }
        }

        // Cap diagnostics at maxDiagnostics
        var cappedDiags = Array(diagnostics.prefix(options.maxDiagnostics))

        // In strict mode, escalate reservedCharacter warnings to errors
        if options.strictRecovery {
            cappedDiags = cappedDiags.map { d in
                if d.code == .reservedCharacter && d.severity == .warning {
                    return Diagnostic(severity: .error, code: d.code, message: d.message, source: d.source)
                }
                return d
            }
        }

        let score = Score(
            source: fileSource,
            dialect: dialect,
            creator: nil,
            charset: nil,
            footer: fileFooter,
            tunes: tunes,
            freeText: [],
            typesetText: [],
            diagnostics: cappedDiags
        )
        return (score, cappedDiags)
    }

    private func isCeolKitDirective(_ name: String) -> Bool {
        name.hasPrefix("ceolkit:")
    }

    private func isStandardDirective(_ name: String) -> Bool {
        name == "landscape" || name == "flatbeams" || name == "writefields"
            || name == "dateformat" || name == "footer"
            || name == "straightflags" || name == "graceslurs"
            || name == "score" || name == "staves" || name == "newpage"
    }

    /// The argument of a `%%newpage` (ABC v2.2 §11.4.7, issue #140): the number the new page
    /// is to print, or `nil` for the bare directive, which leaves the count alone.
    ///
    /// The argument is optional, so a payload that does not parse is a bad *option* on a
    /// directive that is otherwise perfectly clear.  The break is kept and only the
    /// renumbering dropped — the author unmistakably asked for a page break, and refusing to
    /// draw one because the number beside it was mistyped would lose the part they got right.
    private func parseNewPage(_ payload: String, source: SourceRange,
                              diagnostics: inout [Diagnostic]) -> Int? {
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let n = Int(trimmed), n >= 1 { return n }
        diagnostics.append(Diagnostic(
            severity: .warning, code: .invalidPageNumber,
            message: "%%newpage expects no argument or an integer ≥ 1 (got '\(trimmed)'); "
                   + "the page break stands and the numbering is left alone",
            source: source
        ))
        return nil
    }

    // MARK: - Orientation changes

    /// Pairs each `%%landscape` with the `%%newpage` written at the same point, and drops the
    /// ones that have no break to start at (issue #158).
    ///
    /// A page size cannot change part-way down a page, so a change of orientation is only
    /// expressible at a page boundary.  The boundary has to be one the *author* wrote: taking
    /// effect at whatever break happens to come next would let a `%%landscape` with no
    /// `%%newpage` near it reorient a page some distance further on, which is not readable
    /// from the source.  So a request is honoured where a break falls at the same place it
    /// was written — the gap in front of a tune and that tune's header both break before
    /// stave 0, and a body directive breaks before the stave enclosing it — and is otherwise
    /// dropped with a diagnostic.
    ///
    /// Several requests can land on one break; the last one written wins, as it does for
    /// every other directive.
    private func resolvingOrientations(_ requests: [OrientationRequest],
                                       against breaks: [PageBreak],
                                       into diagnostics: inout [Diagnostic]) -> [PageBreak] {
        guard !requests.isEmpty else { return breaks }
        var resolved = breaks
        for request in requests.sorted(by: { $0.source.line < $1.source.line }) {
            // The last break at the stave, because that is the one whose page the music
            // after the directive lands on — the same break `%%newpage N` renumbers.
            guard let index = resolved.lastIndex(where: { $0.beforeStave == request.stave })
            else {
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .landscapeWithoutPageBreak,
                    message: "%%landscape with no %%newpage at the same point cannot change "
                           + "the page size, which only a page boundary can; ignored",
                    source: request.source
                ))
                continue
            }
            let existing = resolved[index]
            resolved[index] = PageBreak(beforeStave: existing.beforeStave,
                                        restartingAt: existing.restartingAt,
                                        landscape: request.landscape,
                                        source: existing.source)
        }
        return resolved
    }

    // MARK: - Tune builder

    private func buildTune(_ abcTune: ABCTune, dialect: Dialect)
    -> (Tune, [Diagnostic], [OrientationRequest]) {
        var diagnostics: [Diagnostic] = []
        var ctx = TuneContext()

        for field in abcTune.headerFields {
            applyHeaderField(field, to: &ctx, diagnostics: &diagnostics)
        }

        // Emit missingRequiredField if X: was absent (set by ABCFileBuilder recovery)
        if abcTune.missingReferenceNumber {
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .missingRequiredField,
                message: "X: field is required",
                source: abcTune.source
            ))
        }

        // Process header directives (%%ceolkit:* etc.)
        let tuneDirectives = processDirectives(abcTune.headerDirectives, scope: .tuneGlobal, diagnostics: &diagnostics)

        // A `%%newpage` in the header breaks before the tune's first stave — the whole tune
        // starts a fresh page.
        var headerBreaks: [PageBreak] = []
        for (name, payload, src) in abcTune.headerDirectives where name == "newpage" {
            headerBreaks.append(PageBreak(
                beforeStave: 0,
                restartingAt: parseNewPage(payload, source: src, diagnostics: &diagnostics),
                source: src))
        }

        // A `%%landscape` in the header asks the tune's first page to turn, so it is matched
        // against a break before stave 0 — the tune's own, or the one in the gap above it.
        var headerOrientations: [OrientationRequest] = []
        for scope in tuneDirectives {
            guard case .landscape(let on) = scope.directive else { continue }
            headerOrientations.append(
                OrientationRequest(landscape: on, stave: 0, source: scope.source))
        }

        // Resolve unitNoteLength from meter if not explicit
        if ctx.unitNoteLength == nil {
            ctx.unitNoteLength = defaultUnitNoteLength(for: ctx.meter)
        }

        let unitLen = ctx.unitNoteLength ?? Fraction(numerator: 1, denominator: 8)
        let meter = ctx.meter ?? .fraction(num: 4, den: 4)

        // K: is required; synthesise C major if missing
        let key: KeySignature
        if let k = ctx.key {
            key = k
        } else {
            let src = abcTune.source
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .missingRequiredField,
                message: "K: field is required; defaulting to C major",
                source: src
            ))
            key = defaultCMajor(source: src)
        }

        // Walk the music body, building voice data
        var bodyCtx = BodyContext(
            unitNoteLength: unitLen,
            meter: meter,
            key: key,
            userSymbols: ctx.userSymbols,
            headerVoices: ctx.headerVoices,
            headerVoiceOrder: ctx.headerVoiceOrder,
            linebreakChars: ctx.linebreakChars,
            linebreakOnEOL: ctx.linebreakOnEOL
        )
        walkBody(abcTune.musicBody, ctx: &bodyCtx, diagnostics: &diagnostics)

        let metadata = buildMetadata(ctx)

        // Build voices (default voice first, then others in order)
        let (voices, voiceDiags) = buildVoices(bodyCtx, tuneSource: abcTune.source)
        diagnostics += voiceDiags

        let tune = Tune(
            reference: ctx.reference ?? 0,
            titles: ctx.titles,
            metadata: metadata,
            key: key,
            meter: meter,
            unitNoteLength: unitLen,
            tempo: ctx.tempo,
            parts: ctx.parts,
            voices: voices,
            userSymbols: ctx.userSymbols,
            macros: ctx.macros,
            directives: tuneDirectives + bodyCtx.bodyTuneDirectives,
            staffPlans: initialStaffPlans(from: tuneDirectives) + bodyCtx.bodyStaffPlans,
            pageBreaks: headerBreaks + bodyCtx.bodyPageBreaks,
            source: abcTune.source
        )
        return (tune, diagnostics, headerOrientations + bodyCtx.bodyOrientations)
    }

    // MARK: - Header parsing

    private func applyHeaderField(
        _ field: InformationField,
        to ctx: inout TuneContext,
        diagnostics: inout [Diagnostic]
    ) {
        switch field {
        case .referenceNumber(let n, _): ctx.reference = n
        case .title(let t):             ctx.titles.append(t)
        case .key(let k):               ctx.key = k
        case .meter(let m, _):          ctx.meter = m
        case .unitNoteLength(let f, _): ctx.unitNoteLength = f
        case .tempo(let t, _):          ctx.tempo = t
        case .parts(let p):             ctx.parts = p
        case .voice(let id, let props, _):
            if ctx.headerVoices.updateValue(props, forKey: id) == nil {
                ctx.headerVoiceOrder.append(id)
            }
        case .userSymbol(let ch, let d, _): ctx.userSymbols[ch] = d
        case .macro(let pat, let exp, let src):
            ctx.macros.append(MacroDefinition(pattern: pat, expansion: exp, source: src))
        case .composer(let t):          ctx.composer = t
        case .origin(let t):
            let parts = t.value.components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            ctx.origins.append(contentsOf: parts)
        case .area(let t):              ctx.area = t
        case .book(let t):              ctx.book = t
        case .discography(let t):       ctx.discography = t
        case .fileUrl(let t):           ctx.fileURL = URL(string: t.value)
        case .group(let t):             ctx.group = t
        case .history(let t):           ctx.history.append(t)
        case .notes(let t):             ctx.notes = t
        case .sourceText(let t):        ctx.sourceText = t
        case .rhythm(let t):            ctx.rhythm = t
        case .transcription(let t):     ctx.transcription = t
        case .instruction(let t):
            let parts = t.value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.first?.lowercased() == "linebreak" {
                // ABC 2.2 §9.2: fixed vocabulary — <EOL>, <none>, $, !
                // <none> resets everything; other tokens accumulate.
                var chars: Set<Character> = []
                var eol = false
                for token in parts.dropFirst() {
                    switch token {
                    case "<EOL>":  eol = true
                    case "<none>": chars = []; eol = false
                    case "$":      chars.insert("$")
                    case "!":      chars.insert("!")  // ambiguous with decorations; best-effort
                    default:       break               // ignore unrecognised tokens
                    }
                }
                ctx.linebreakChars = chars
                ctx.linebreakOnEOL = eol
            }
        default:                        break
        }
    }

    // MARK: - Music body walker

    private func walkBody(
        _ body: [[MusicElement]],
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        // The one cursor in the pass, threaded from here down.  It is a parameter rather than
        // a field on BodyContext so nothing can read "the current voice" implicitly.
        var voice = ctx.initialVoice
        // Where each line-set ends, worked out ahead of the walk because it takes the *next*
        // line to know: a system ends where the source starts writing a voice it has already
        // written here.  Under `I:linebreak <none>` or `$` alone the end of a line is not a
        // break at all, and only an explicit `$`/`!` splits a stave.
        let lineSetEnds = ctx.linebreakOnEOL
            ? lineSetBoundaries(body, initialVoice: ctx.initialVoice)
            : []
        for (index, line) in body.enumerated() {
            // Check if this is a single-field lyric line
            if isLyricLine(line), case .inlineField(let f, _) = line[0], case .lyric(let tokens, _) = f {
                // §7.4: "disregarding any overlay in the accompanying music code" — the
                // syllables belong to the voice, not to whichever `&` layer the line above
                // left the cursor standing in.
                ctx.applyLyrics(tokens, in: voice.primary)
                continue
            }
            // A line beginning `&` overlays the line above it, so it takes neither a stave of
            // its own nor a lyric anchor of its own: §7.4 matches `w:` to the notes
            // "disregarding any overlay in the accompanying music code", and the notes it
            // means are the ones above.  The cursor stays where that line left it too, so
            // this line's leading `&` opens the *next* layer over the same music: three parts
            // written as three lines and three parts written on one line with two `&`s are
            // the same tune.
            if !continuesOverlay(line) {
                ctx.recordLyricAnchors()
                // An ordinary line opens in the voice itself: an `&` layer lives to the end
                // of the line that opened it, and the next line's first `&` reopens layer one.
                voice = voice.primary
            }
            walkLine(line, voice: &voice, ctx: &ctx, diagnostics: &diagnostics)
            if lineSetEnds.contains(index) { ctx.closeLineSet() }
        }
    }

    /// The body lines each line-set ends at.
    ///
    /// A line-set is what the source lays out as one system, and the parser is handed a flat
    /// stream of lines with no marker between them.  What identifies one is the voices: a run
    /// of lines in which each voice appears once, ending as soon as a line writes to a voice
    /// the run already holds.  A source that writes each voice as a whole block instead falls
    /// out of the same rule — every one of its lines is a line-set of its own, which is what
    /// keeps each voice counting its own staves from zero.
    ///
    /// The boundary is reported against the last line that *wrote* something, not the line
    /// that begins the next set, so the `V:` and `%%score` lines introducing a system are
    /// walked on its far side — a plan written there governs from the stave it stands above.
    private func lineSetBoundaries(_ body: [[MusicElement]], initialVoice: VoiceKey) -> Set<Int> {
        var boundaries: Set<Int> = []
        var current = initialVoice.base
        var written: Set<String> = []
        var lastContentLine: Int? = nil

        for (index, line) in body.enumerated() {
            if isLyricLine(line) { continue }
            // An `&` continuation belongs to the line above it, so it neither opens a set nor
            // may be cut away from the music it overlays.
            if continuesOverlay(line) {
                lastContentLine = index
                continue
            }
            var voicesWritten: Set<String> = []
            for element in line {
                switch element {
                case .inlineField(let field, _):
                    if case .voice(let id, _, _) = field { current = id }
                case .space, .voiceOverlay, .unknown:
                    continue
                default:
                    voicesWritten.insert(current)
                }
            }
            guard !voicesWritten.isEmpty else { continue }
            if !voicesWritten.isDisjoint(with: written), let end = lastContentLine {
                boundaries.insert(end)
                written = []
            }
            written.formUnion(voicesWritten)
            lastContentLine = index
        }
        // The body ends the line-set it is in, at the last line that wrote anything: a
        // `%%score` trailing the music governs from the stave after it, not from the last one
        // written.
        if let end = lastContentLine { boundaries.insert(end) }
        return boundaries
    }

    /// Whether `line` is a lyric line — a `w:` on its own, which belongs to the music above
    /// it and is neither music nor a line-set of its own.
    private func isLyricLine(_ line: [MusicElement]) -> Bool {
        guard line.count == 1, case .inlineField(let field, _) = line[0],
              case .lyric = field else { return false }
        return true
    }

    /// Whether `line` is the continuation of the one before it — an `&` overlay written on
    /// its own source line, which shares a stave and a lyric anchor with what it overlays.
    private func continuesOverlay(_ line: [MusicElement]) -> Bool {
        for element in line {
            switch element {
            case .space: continue
            case .voiceOverlay: return true
            default: return false
            }
        }
        return false
    }

    private func walkLine(
        _ elements: [MusicElement],
        voice: inout VoiceKey,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        // Pre-pass: resolve broken rhythms so note durations are correct
        let resolved = resolveBrokenRhythms(elements)

        var index = resolved.startIndex
        while index < resolved.endIndex {
            // §7.4: each `&` sets the time point back by one bar line, so a run of them winds
            // back that many — `&&` under a two-bar line overlays both of its bars.  Read here
            // rather than in the parser: the count is an interpretation of the syntax, and the
            // AST keeps one node per character the source wrote.
            guard case .voiceOverlay(let src) = resolved[index] else {
                walkElement(resolved[index], voice: &voice, ctx: &ctx, diagnostics: &diagnostics)
                index += 1
                continue
            }
            var bars = 1
            while index + bars < resolved.endIndex,
                  case .voiceOverlay = resolved[index + bars] { bars += 1 }
            openOverlay(rewinding: bars, source: src, voice: &voice, ctx: &ctx,
                        diagnostics: &diagnostics)
            index += bars
        }
        // Finish any open grace group (malformed; just close it)
        if ctx.isInGrace(voice) {
            ctx.flushGrace(in: voice)
        }
        // A tuplet does not run past the end of the line that opened it: whatever it collected
        // is written here rather than left hanging, where the next line would drop it (#86).
        for abandoned in ctx.flushOpenTuplets() {
            diagnostics.append(incompleteTuplet(abandoned))
        }
    }

    /// The warning for a tuplet that ended before the `r` notes it asked for.
    private func incompleteTuplet(_ open: TupletState) -> Diagnostic {
        let kept = open.musicalEventCount
        return Diagnostic(
            severity: .warning, code: .incompleteTuplet,
            message: "this tuplet asks for \(open.r) notes but "
                   + (kept == 0 ? "none follow it" : "only \(kept) follow it"),
            source: open.source,
            hint: kept == 0
                ? "a tuplet's notes follow it directly; nothing was collected here, so nothing "
                + "is drawn for it."
                : "the \(kept) note\(kept == 1 ? "" : "s") written are kept, as a tuplet of "
                + "\(kept).")
    }

    /// Moves the cursor into the temporary voice a run of `bars` `&`s opens (§7.4).
    ///
    /// The clock is wound back over `bars` bar lines: back to the head of the bar now being
    /// written, and then one whole bar further for each `&` after the first.  A `&` written
    /// where no bar has begun — at the head of a line, or of the tune — winds back from the
    /// last bar line instead, which is what makes the standard's own `&&` example overlay the
    /// two bars of the line above rather than the two after them.
    private func openOverlay(
        rewinding bars: Int,
        source: SourceRange,
        voice: inout VoiceKey,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        // Whatever the layer being left holds open is finished before the clock moves.
        if ctx.isInGrace(voice) { ctx.flushGrace(source: source, in: voice) }
        if let abandoned = ctx.flushTuplet(in: voice) {
            diagnostics.append(incompleteTuplet(abandoned))
        }

        let primary = ctx.voice(voice.primary)?.accumulator
        let closed = primary?.closedMeasures.count ?? 0
        let openBar = primary?.hasOpenMeasure ?? false
        let start = closed - (bars - 1) - (openBar ? 0 : 1)
        if start < 0 {
            diagnostics.append(Diagnostic(
                severity: .warning, code: .voiceOverlayWithoutBar,
                message: "\(bars == 1 ? "an &" : "\(bars) &s") here would set the time point "
                       + "back before the first bar of this voice; the overlay starts at that bar",
                source: source,
                hint: "each & sets the time point back by one bar line (§7.4), so there must be "
                    + "at least that many bars of music before it."))
        }
        voice = voice.nextOverlay
        ctx.openOverlay(voice, startingAt: max(0, start), source: source)
    }

    private func walkElement(
        _ elem: MusicElement,
        voice: inout VoiceKey,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        let prevWasSpace = ctx.lastElementWasSpace(in: voice)
        ctx.setLastElementWasSpace(false, in: voice)

        switch elem {
        case .note(let tok):
            let event = buildNoteEvent(tok, voice: voice, ctx: &ctx)
            ctx.emit(event, in: voice)

        case .chord(let notes, let src):
            let event = buildChordEvent(notes, source: src, voice: voice, ctx: &ctx)
            ctx.emit(event, in: voice)

        case .rest(let kind, let dur, let src):
            let duration = resolveDuration(dur)
            let decorations = ctx.flushDecorations(in: voice, source: src)
            let rest = Rest(kind: kind, duration: duration, decorations: decorations, source: src)
            ctx.emit(.rest(rest), in: voice)

        case .barLine(let kind, let src):
            // A tuplet does not span a bar line, so one still open here is short of what it
            // asked for; it is written into the bar being closed rather than lost with it (#86).
            if let abandoned = ctx.flushTuplet(in: voice) {
                diagnostics.append(incompleteTuplet(abandoned))
            }
            // Closes this bar for every `&` layer standing in it, not just the current one:
            // the bar line is the staff's, and §7.4 overlays share the bar it ends.
            ctx.closeBar(barLine: BarLine(kind: kind, source: src), in: voice)

        case .inlineField(let field, let src):
            applyInlineField(field, source: src, voice: &voice, ctx: &ctx, diagnostics: &diagnostics)

        case .graceStart(let acciaccatura, let src):
            ctx.startGrace(acciaccatura: acciaccatura, source: src, in: voice)

        case .graceEnd(let src):
            ctx.flushGrace(source: src, in: voice)

        case .decoration(let tok, let src):
            let decoration = expandDecoration(tok, userSymbols: ctx.userSymbols)
            // Post-note decoration: if preceded by a space and there's a note in currentEvents,
            // apply retroactively to the preceding note.
            if prevWasSpace && ctx.applyDecorationToLastNote(decoration, in: voice) {
                // Applied retroactively
            } else {
                ctx.addPendingDecoration(decoration, in: voice, source: src)
            }

        case .annotation(let pos, let text, let src):
            ctx.addPendingAnnotation(Annotation(
                position: pos,
                text: TextString(value: text, source: src),
                source: src
            ), in: voice)

        case .chordSymbol(let s, let src):
            ctx.setPendingChordSymbol(parseChordSymbol(s, source: src), in: voice, source: src)

        case .tupletStart(let p, let q, let r, let src):
            // Tuplets do not nest: a second one closes the first, which keeps what the first
            // had collected instead of clobbering it (#86).
            if let abandoned = ctx.flushTuplet(in: voice) {
                diagnostics.append(incompleteTuplet(abandoned))
            }
            let resolvedQ = q ?? defaultQ(p: p, meter: ctx.meter)
            let resolvedR = r ?? p
            ctx.startTuplet(p: p, q: resolvedQ, r: resolvedR, source: src, in: voice)

        case .slurOpen(let src):
            ctx.openSlur(in: voice, source: src)

        case .slurClose(let src):
            // `)` is a post-fix on the preceding note, not a prefix for the next.
            // Retroactively add the close to the last emitted note so that
            // `(A2 | A2) B` gives A2 `closes:1`, not B.
            if !ctx.addSlurCloseToLastNote(in: voice) {
                ctx.carrySlurClose(in: voice, source: src)   // fallback: no note yet, carry forward
            }

        case .endingNumber(let nums, let src):
            ctx.setPendingEndingNumber(nums, in: voice, source: src)

        case .space(let src):
            ctx.emitSpaceBreak(source: src, in: voice)
            ctx.setLastElementWasSpace(true, in: voice)

        case .voiceOverlay:
            break  // read as a run by `walkLine`, which never hands one down here

        case .brokenRhythm:
            break  // already handled in resolveBrokenRhythms pre-pass

        case .unknown(let ch, let src):
            if ctx.linebreakChars.contains(ch) {
                ctx.splitStave(in: voice.primary)
            } else {
                let severity: Diagnostic.Severity = options.strictRecovery ? .error : .warning
                diagnostics.append(Diagnostic(
                    severity: severity, code: .reservedCharacter,
                    message: "Unknown element in music body",
                    source: src
                ))
            }
        }
    }

    // MARK: - Note / chord building

    private func buildNoteEvent(_ tok: NoteToken, voice: VoiceKey, ctx: inout BodyContext) -> Event {
        let step = diatonicStep(from: tok.pitchLetter)
        // ABC octave convention: uppercase C..B = octave 4 (middle C = C4), lowercase c..b = octave 5
        let baseOctave = tok.pitchLetter.isUppercase ? 4 : 5
        let octave = baseOctave + tok.octaveMarks

        let currentResolved = ctx.resolveAccidental(step: step, octave: octave, in: voice)
        let writtenAlt = tok.accidental.map { alterationFromToken($0) }
        let playedAlt: Alteration
        let displayedAlt: Alteration?
        if let written = writtenAlt {
            playedAlt = written
            // displayedAccidental is nil when the accidental is redundant (bar memory already implies it)
            displayedAlt = (written == currentResolved) ? nil : written
            ctx.recordAccidental(step: step, octave: octave, alteration: written, in: voice, source: tok.source)
        } else {
            playedAlt = currentResolved
            displayedAlt = nil
        }

        let pitch = Pitch(step: step, alteration: playedAlt, octave: octave)
        let duration = resolveDuration(tok.duration)
        let tieState: TieState = tok.tie ? .startsTie : .none
        let (opens, closes) = ctx.consumeSlurs(in: voice, source: tok.source)

        let note = Note(
            pitch: pitch,
            writtenAccidental: writtenAlt,
            displayedAccidental: displayedAlt,
            duration: duration,
            ties: tieState,
            slurs: SlurState(opens: opens, closes: closes),
            decorations: ctx.flushDecorations(in: voice, source: tok.source),
            chordSymbol: ctx.flushChordSymbol(in: voice, source: tok.source),
            annotations: ctx.flushAnnotations(in: voice, source: tok.source),
            beam: .single,
            lyric: nil,
            source: tok.source
        )

        if ctx.isInGrace(voice) {
            ctx.appendGraceNote(note, in: voice)
            return .note(note)  // returned but not emitted directly; grace buffer holds it
        }
        if ctx.isInTuplet(voice) {
            return .note(note)  // will be handed to tuplet collector
        }
        return .note(note)
    }

    private func buildChordEvent(
        _ notes: [NoteToken],
        source: SourceRange,
        voice: VoiceKey,
        ctx: inout BodyContext
    ) -> Event {
        let resolvedNotes: [Note] = notes.map { tok in
            let step = diatonicStep(from: tok.pitchLetter)
            let baseOctave = tok.pitchLetter.isUppercase ? 4 : 5
            let octave = baseOctave + tok.octaveMarks

            let currentResolved = ctx.resolveAccidental(step: step, octave: octave, in: voice)
            let writtenAlt = tok.accidental.map { alterationFromToken($0) }
            let playedAlt: Alteration
            let displayedAlt: Alteration?
            if let written = writtenAlt {
                playedAlt = written
                displayedAlt = (written == currentResolved) ? nil : written
                ctx.recordAccidental(step: step, octave: octave, alteration: written, in: voice, source: tok.source)
            } else {
                playedAlt = currentResolved
                displayedAlt = nil
            }

            let pitch = Pitch(step: step, alteration: playedAlt, octave: octave)
            let duration = resolveDuration(tok.duration)
            let tieState: TieState = tok.tie ? .startsTie : .none
            return Note(
                pitch: pitch,
                writtenAccidental: writtenAlt,
                displayedAccidental: displayedAlt,
                duration: duration,
                ties: tieState,
                slurs: .none,
                decorations: [],
                chordSymbol: nil,
                annotations: [],
                beam: .single,
                lyric: nil,
                source: tok.source
            )
        }

        let duration = resolvedNotes.first?.duration ?? Fraction(numerator: 1, denominator: 8)
        let tieState: TieState = resolvedNotes.contains { $0.ties == .startsTie } ? .startsTie : .none
        let (opens, closes) = ctx.consumeSlurs(in: voice, source: source)

        let chord = Chord(
            notes: resolvedNotes,
            duration: duration,
            decorations: ctx.flushDecorations(in: voice, source: source),
            chordSymbol: ctx.flushChordSymbol(in: voice, source: source),
            annotations: ctx.flushAnnotations(in: voice, source: source),
            beam: .single,
            ties: tieState,
            slurs: SlurState(opens: opens, closes: closes),
            lyric: nil,
            source: source
        )
        return .chord(chord)
    }

    // MARK: - Inline field handling

    private func applyInlineField(
        _ field: InformationField,
        source: SourceRange,
        voice: inout VoiceKey,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        switch field {
        case .key(let k):
            ctx.setKey(k, in: voice, source: source)
        case .meter(let m, _):
            ctx.setMeter(m, in: voice)
        case .unitNoteLength(let f, _):
            ctx.setUnitNoteLength(f, in: voice, source: source)
        case .tempo(let t, _):
            ctx.emit(.tempoChange(t), in: voice)
        case .voice(let id, let props, _):
            ctx.registerVoice(id: id, properties: props)
            // The one place the cursor moves between voices.  It lands on the voice itself,
            // never on one of its `&` layers: those belong to the line that opened them.
            voice = VoiceKey(id)
        case .lyric(let tokens, _):
            // §7.4: syllables match the notes "disregarding any overlay in the accompanying
            // music code", so they land on the voice even when an `&` layer is being written.
            ctx.applyLyrics(tokens, in: voice.primary)
        case .userSymbol(let ch, let dec, _):
            ctx.userSymbols[ch] = dec
        case .instruction(let t)
            where t.value.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("abc-include"):
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: .includeIgnoredInline,
                message: "I:abc-include has no effect as an inline field",
                source: source
            ))
        case .instruction(let t):
            // §4.4: `I:name payload` is the stylesheet directive `%%name payload`.  A `%%`
            // line interrupting a `\\` continuation is spliced in as one of these, and a
            // source may write one directly.  The instructions that configure the *parser*
            // are not stylesheet directives and are handled (or ignored) elsewhere.
            guard let directive = stylesheetDirective(fromInstruction: t) else { break }
            applyBodyDirective(
                name: directive.name, payload: directive.payload,
                source: source, voice: voice.base, ctx: &ctx, diagnostics: &diagnostics
            )
        case .unknown(let code, let payload, let src) where String(code) == "%":
            // Body-level directive stored by ABCFileBuilder as .unknown(code:"%", payload:"name payload")
            let parts = payload.split(separator: " ", maxSplits: 1)
            let dirName = parts.first.map(String.init) ?? payload
            let dirPayload = parts.count > 1 ? String(parts[1]) : ""
            applyBodyDirective(
                name: dirName, payload: dirPayload, source: src,
                voice: voice.base, ctx: &ctx, diagnostics: &diagnostics
            )
        default:
            break
        }
    }

    private func applyBodyDirective(
        name: String,
        payload: String,
        source: SourceRange,
        voice: String,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        switch name {
        case "ceolkit:stemalignment":
            if ctx.hasExplicitVoice {
                var tempDiags: [Diagnostic] = []
                if let d = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &tempDiags) {
                    let vid = VoiceId.named(voice)
                    let scope = Scope.voiceLocal(vid)
                    ctx.voiceDirectives[voice, default: []].append(
                        CeolKitDirectiveScope(directive: d, scope: scope, source: source)
                    )
                }
                diagnostics += tempDiags
            } else {
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .misplacedStemAlignment,
                    message: "%%ceolkit:stemalignment requires a preceding V: field",
                    source: source
                ))
            }
        case "score", "staves":
            // §11.1: a plan in the body resets the music generator from here on, so unlike
            // every other directive its position is part of what it means.
            var tempDiags: [Diagnostic] = []
            if let d = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &tempDiags) {
                ctx.bodyTuneDirectives.append(CeolKitDirectiveScope(directive: d, scope: .tuneGlobal, source: source))
                if case .staffPlan(let plan) = d {
                    // The plan can only change where the staves of a system do, so one
                    // written inside a stave governs the whole of the stave enclosing it
                    // rather than breaking the system where it happens to fall.
                    if ctx.hasStaveInProgress {
                        tempDiags.append(Diagnostic(
                            severity: .warning, code: .staffPlanSnappedToStave,
                            message: "%%\(name) inside a stave takes effect from the start of that stave",
                            source: source
                        ))
                    }
                    ctx.bodyStaffPlans.append(StaffPlanChange(
                        plan: plan,
                        effectiveFromStave: ctx.currentStaveIndex,
                        source: source
                    ))
                }
            }
            diagnostics += tempDiags
        case "newpage":
            // §11.4.7: the music from here on starts a fresh page.  Like a staff plan, and
            // for the same reason — the staves of a system are laid out together — a break
            // written part-way through one snaps back to the start of the stave enclosing it.
            if ctx.hasStaveInProgress {
                diagnostics.append(Diagnostic(
                    severity: .warning, code: .pageBreakSnappedToStave,
                    message: "%%newpage inside a stave takes effect from the start of that stave",
                    source: source
                ))
            }
            ctx.bodyPageBreaks.append(PageBreak(
                beforeStave: ctx.currentStaveIndex,
                restartingAt: parseNewPage(payload, source: source, diagnostics: &diagnostics),
                source: source))
        case "landscape", "flatbeams", "ceolkit:justifylast", "ceolkit:scale",
             "ceolkit:gracenotespacing", "writefields",
             "dateformat", "footer", "straightflags", "graceslurs":
            var tempDiags: [Diagnostic] = []
            if let d = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &tempDiags) {
                ctx.bodyTuneDirectives.append(CeolKitDirectiveScope(directive: d, scope: .tuneGlobal, source: source))
                // §11.4.7 / issue #158: a page turns only where a page breaks, so a
                // `%%landscape` in the body is recorded against the stave enclosing it — the
                // same stave a `%%newpage` written beside it breaks before.
                if case .landscape(let on) = d {
                    ctx.bodyOrientations.append(
                        OrientationRequest(landscape: on, stave: ctx.currentStaveIndex,
                                           source: source))
                }
            }
            diagnostics += tempDiags
        default:
            diagnostics.append(Diagnostic(
                severity: .info, code: .unknownDirective,
                message: "Unsupported stylesheet directive '%%\(name)'",
                source: source
            ))
        }
    }

    // MARK: - Broken rhythm pre-pass

    private func resolveBrokenRhythms(_ elements: [MusicElement]) -> [MusicElement] {
        var result: [MusicElement] = []
        var i = 0
        while i < elements.count {
            let elem = elements[i]
            switch elem {
            case .brokenRhythm(let count, let direction, _):
                // Modify the last note in result (left side) and peek at next note (right side).
                let (leftMul, rightMul) = brokenMultipliers(count: count, direction: direction)
                // Adjust left
                if !result.isEmpty {
                    result[result.count - 1] = applyDurationMultiplier(leftMul, to: result[result.count - 1])
                }
                // Advance to the right-side note, passing any intervening grace groups through
                // unchanged. A grace group is a graceStart…graceEnd bracket with notes inside;
                // consuming it here preserves order without losing the pending modifier.
                i += 1
                while i < elements.count, case .graceStart = elements[i] {
                    while i < elements.count {
                        let g = elements[i]
                        result.append(g)
                        i += 1
                        if case .graceEnd = g { break }
                    }
                }
                if i < elements.count {
                    result.append(applyDurationMultiplier(rightMul, to: elements[i]))
                }
            default:
                result.append(elem)
            }
            i += 1
        }
        return result
    }

    // Returns (leftMultiplier, rightMultiplier) as (num, den) pairs.
    // For direction .right, count n: left = (2^(n+1)-1) / 2^n, right = 1 / 2^n
    // For direction .left:          left = 1 / 2^n,            right = (2^(n+1)-1) / 2^n
    private func brokenMultipliers(count: Int, direction: BrokenDirection) -> ((Int, Int), (Int, Int)) {
        let den = 1 << count            // 2^n
        let longNum = (1 << (count + 1)) - 1  // 2^(n+1) - 1
        switch direction {
        case .right: return ((longNum, den), (1, den))
        case .left:  return ((1, den), (longNum, den))
        }
    }

    private func applyDurationMultiplier(_ multiplier: (Int, Int), to element: MusicElement) -> MusicElement {
        let (mNum, mDen) = multiplier
        switch element {
        case .note(let tok):
            let newDur = DurationToken(
                numerator:   tok.duration.numerator   * mNum,
                denominator: tok.duration.denominator * mDen
            )
            return .note(NoteToken(
                accidental: tok.accidental,
                pitchLetter: tok.pitchLetter,
                octaveMarks: tok.octaveMarks,
                duration: newDur,
                tie: tok.tie,
                source: tok.source
            ))
        case .rest(let kind, let dur, let src):
            return .rest(
                kind: kind,
                duration: DurationToken(numerator: dur.numerator * mNum, denominator: dur.denominator * mDen),
                source: src
            )
        default:
            return element
        }
    }

    // MARK: - Helpers

    private func diatonicStep(from ch: Character) -> DiatonicStep {
        switch ch.uppercased().first {
        case "C": return .c
        case "D": return .d
        case "E": return .e
        case "F": return .f
        case "G": return .g
        case "A": return .a
        case "B": return .b
        default:  return .c
        }
    }

    private func alterationFromToken(_ tok: AccidentalToken) -> Alteration {
        switch tok {
        case .sharp:        return .sharp
        case .doubleSharp:  return .doubleSharp
        case .flat:         return .flat
        case .doubleFlat:   return .doubleFlat
        case .natural:      return .natural
        case .microtonal(let sign, let num, let den):
            return Alteration.reduced(numerator: sign * num, denominator: den)
        }
    }

    // Note.duration is expressed in unit note lengths (not whole-note fractions).
    // DurationToken.numerator/denominator is already in those units; just reduce it.
    private func resolveDuration(_ dur: DurationToken) -> Fraction {
        reducedFraction(numerator: dur.numerator, denominator: dur.denominator)
    }

    // Default q for tuplet (number of normal-note beats in the time of p tuplet notes)
    private func defaultQ(p: Int, meter: Meter?) -> Int {
        switch meter {
        case .fraction(let n, _) where n >= 6 && n % 3 == 0:
            // compound: default q = next smaller power-of-two × 3 ÷ 2
            return p % 3 == 0 ? (p / 3) * 2 : 2
        default:
            return 2
        }
    }

    private func defaultUnitNoteLength(for meter: Meter?) -> Fraction {
        switch meter {
        case .fraction(let n, let d):
            let ratio = Double(n) / Double(d)
            return ratio < 0.75 ? Fraction(numerator: 1, denominator: 16)
                                : Fraction(numerator: 1, denominator: 8)
        case .commonTime:
            return Fraction(numerator: 1, denominator: 8)   // 4/4 ≥ 0.75
        case .cutTime:
            return Fraction(numerator: 1, denominator: 8)   // 2/2 = 1.0 ≥ 0.75
        default:
            return Fraction(numerator: 1, denominator: 8)
        }
    }

    private func defaultCMajor(source: SourceRange) -> KeySignature {
        KeySignature(
            tonic: PitchClass(step: .c, alteration: .natural),
            mode: .major,
            modifications: [],
            explicit: false,
            clef: ClefSpec(clef: .treble, octaveShift: 0),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: 5),
            source: source
        )
    }

    // Chord symbol parsing: minimal stub — preserves raw text without structural parsing
    private func parseChordSymbol(_ raw: String, source: SourceRange) -> ChordSymbol? {
        guard !raw.isEmpty else { return nil }
        var idx = raw.startIndex
        guard idx < raw.endIndex, let step = letterToDiatonicStep(raw[idx]) else { return nil }
        raw.formIndex(after: &idx)
        var alteration = Alteration.natural
        if idx < raw.endIndex {
            switch raw[idx] {
            case "#": alteration = .sharp;   raw.formIndex(after: &idx)
            case "b": alteration = .flat;    raw.formIndex(after: &idx)
            default: break
            }
        }
        let root = PitchClass(step: step, alteration: alteration)

        var quality = String(raw[idx...])
        var bassNote: PitchClass? = nil
        if let slashRange = quality.range(of: "/") {
            let afterSlash = String(quality[quality.index(after: slashRange.lowerBound)...])
            quality = String(quality[..<slashRange.lowerBound])
            if let bassStep = afterSlash.first.flatMap({ letterToDiatonicStep($0) }) {
                var bassAlt = Alteration.natural
                let rest = afterSlash.dropFirst()
                if rest.first == "#" { bassAlt = .sharp }
                else if rest.first == "b" { bassAlt = .flat }
                bassNote = PitchClass(step: bassStep, alteration: bassAlt)
            }
        }

        return ChordSymbol(root: root, quality: quality, bassNote: bassNote, raw: raw, source: source)
    }

    private func letterToDiatonicStep(_ ch: Character) -> DiatonicStep? {
        switch ch {
        case "C", "c": return .c
        case "D", "d": return .d
        case "E", "e": return .e
        case "F", "f": return .f
        case "G", "g": return .g
        case "A", "a": return .a
        case "B", "b": return .b
        default: return nil
        }
    }

    // MARK: - Directive processing

    private func processDirectives(
        _ directives: [(name: String, payload: String, source: SourceRange)],
        scope: Scope,
        diagnostics: inout [Diagnostic]
    ) -> [CeolKitDirectiveScope] {
        var result: [CeolKitDirectiveScope] = []
        for (name, payload, source) in directives {
            if let directive = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &diagnostics) {
                result.append(CeolKitDirectiveScope(directive: directive, scope: scope, source: source))
            } else if !name.hasPrefix("ceolkit:") && !isStandardDirective(name) {
                diagnostics.append(Diagnostic(
                    severity: .info,
                    code: .unknownDirective,
                    message: "Unsupported stylesheet directive '%%\(name)'",
                    source: source
                ))
            }
        }
        return result
    }

    /// The opening staff plan `tune` inherits from outside itself, as a change list to put
    /// ahead of its own — empty where it inherits none (issue #157).
    ///
    /// A plan is unlike every other stylesheet directive in that it names voices, and voice
    /// names are a tune's own business: `%%score (T B)` means nothing in a tune whose voices
    /// are called `1` and `2`.  Applying it there would half-apply it — printing nothing the
    /// plan names, and dropping everything it does not — so an inherited plan governs only
    /// where every voice it names exists, and the tune is otherwise laid out as though the
    /// plan had been written for some other document, which is what it was.
    ///
    /// A tune stating its own plan before any music overrides whatever it inherits, so the
    /// inherited plan never gets to govern there.  It is still carried, ahead of the tune's
    /// own and in source order, because that is where it was written; and the fit test does
    /// not apply to it, because a plan that governs nothing cannot misgovern this tune.
    private func fileStaffPlans(
        for tune: Tune,
        from filePlan: StaffPlan?,
        into diagnostics: inout [Diagnostic]
    ) -> [StaffPlanChange] {
        guard let filePlan else { return [] }
        let change = StaffPlanChange(plan: filePlan, effectiveFromStave: 0, source: filePlan.source)
        guard !tune.staffPlans.contains(where: { $0.effectiveFromStave == 0 }) else { return [change] }

        let declared = Set(tune.voices.map(\.id))
        var missing: [VoiceId] = []
        for id in filePlan.namedVoices where !declared.contains(id) && !missing.contains(id) {
            missing.append(id)
        }
        guard missing.isEmpty else {
            let names = missing.map(voiceLabel).joined(separator: ", ")
            diagnostics.append(Diagnostic(
                severity: .info,
                code: .staffPlanNotApplicableToTune,
                message: "staff plan written outside this tune names "
                       + "\(missing.count == 1 ? "voice" : "voices") \(names), which it does not "
                       + "have; the tune is laid out as though the plan were not written",
                source: filePlan.source
            ))
            return []
        }
        return [change]
    }

    private func voiceLabel(_ id: VoiceId) -> String {
        switch id {
        case .named(let name): return "'\(name)'"
        case .all: return "'*'"
        }
    }

    /// The staff plans among `scopes`, each governing from the first stave — the position
    /// of a plan written before any music, in the file preamble or the tune header.
    private func initialStaffPlans(from scopes: [CeolKitDirectiveScope]) -> [StaffPlanChange] {
        scopes.compactMap { scoped in
            guard case .staffPlan(let plan) = scoped.directive else { return nil }
            return StaffPlanChange(plan: plan, effectiveFromStave: 0, source: scoped.source)
        }
    }

    private func parseCeolKitDirective(
        name: String,
        payload: String,
        source: SourceRange,
        diagnostics: inout [Diagnostic]
    ) -> CeolKitDirective? {
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        switch name {
        case "ceolkit:pipeformat":
            if trimmed == "true" { return .pipeFormat(true) }
            if trimmed == "false" { return .pipeFormat(false) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%ceolkit:pipeformat expects 'true' or 'false'", source: source))
            return nil
        case "ceolkit:pagenumber":
            if let n = Int(trimmed) {
                if n < 1 {
                    diagnostics.append(Diagnostic(severity: .warning, code: .invalidPageNumber,
                        message: "%%ceolkit:pagenumber must be ≥ 1 (got \(n))", source: source))
                    return nil
                }
                return .pageNumber(n)
            }
            diagnostics.append(Diagnostic(severity: .warning, code: .invalidPageNumber,
                message: "%%ceolkit:pagenumber expects an integer (got '\(trimmed)')", source: source))
            return nil
        case "ceolkit:stemalignment":
            if let n = Int(trimmed) { return .stemAlignment(n) }
            diagnostics.append(Diagnostic(severity: .warning, code: .misplacedStemAlignment,
                message: "%%ceolkit:stemalignment expects an integer", source: source))
            return nil
        case "ceolkit:scale":
            if let f = Double(trimmed) {
                if f <= 0 || !f.isFinite {
                    diagnostics.append(Diagnostic(severity: .warning, code: .invalidScale,
                        message: "%%ceolkit:scale must be a positive number (got \(trimmed))", source: source))
                    return nil
                }
                return .scale(f)
            }
            diagnostics.append(Diagnostic(severity: .warning, code: .invalidScale,
                message: "%%ceolkit:scale expects a number (got '\(trimmed)')", source: source))
            return nil
        case "ceolkit:gracenotespacing":
            // A factor below 1 steps less than one notehead width, so adjacent grace
            // noteheads within a group would overlap. Rejected rather than clamped, so the
            // tune falls back to the renderer default the way an invalid scale does.
            if let f = Double(trimmed) {
                if f < 1 || !f.isFinite {
                    diagnostics.append(Diagnostic(severity: .warning, code: .invalidGraceNoteSpacing,
                        message: "%%ceolkit:gracenotespacing must be at least 1 grace notehead width (got \(trimmed))",
                        source: source))
                    return nil
                }
                return .graceNoteSpacing(f)
            }
            diagnostics.append(Diagnostic(severity: .warning, code: .invalidGraceNoteSpacing,
                message: "%%ceolkit:gracenotespacing expects a number (got '\(trimmed)')", source: source))
            return nil
        case "landscape":
            if let value = parseLogical(trimmed) { return .landscape(value) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%landscape expects '0'/'false' (portrait) or '1'/'true' (landscape)", source: source))
            return nil
        case "flatbeams":
            if let value = parseLogical(trimmed) { return .flatBeams(value) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%flatbeams expects '0'/'false' or '1'/'true'", source: source))
            return nil
        case "ceolkit:justifylast":
            if let value = parseLogical(trimmed) { return .justifyLast(value) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%ceolkit:justifylast expects 'true' or 'false'", source: source))
            return nil
        case "writefields":
            // Syntax: <fieldList> [true|false]
            // The field list is a run of letters; an optional logical value follows.
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let enabled: Bool
            var fieldList: String
            if let last = parts.last, let b = parseLogical(last) {
                enabled = b
                fieldList = parts.dropLast().joined()
            } else {
                enabled = true
                fieldList = parts.joined()
            }
            return .writeFields(fieldList, enabled)
        case "ceolkit:label":
            // Taken exactly as written, quotes aside: it is the caller's string, and the
            // renderer never expands `$P` or `${…}` inside it (issue #168).
            return .label(stripQuotes(trimmed))
        case "dateformat":
            return .dateFormat(stripQuotes(trimmed))
        case "straightflags":
            if let value = parseLogical(trimmed) { return .straightFlags(value) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%straightflags expects '0'/'false' or '1'/'true'", source: source))
            return nil
        case "graceslurs":
            if let value = parseLogical(trimmed) { return .graceSlurs(value) }
            diagnostics.append(Diagnostic(severity: .warning, code: .unknownDirective,
                message: "%%graceslurs expects '0'/'false' or '1'/'true'", source: source))
            return nil
        case "score", "staves":
            // Both spellings normalise to one StaffPlan; a malformed payload drops the
            // whole directive rather than storing a partial tree (ABC v2.2 §11.1).
            let (plan, planDiags) = StaffPlanParser.parse(name: name, payload: payload, source: source)
            diagnostics += planDiags
            return plan.map { .staffPlan($0) }
        case "footer":
            // %%footer is scoped to the file or the tune header and is resolved directly in
            // build(); silently accept here.
            return nil
        default:
            return nil
        }
    }

    /// The `$`-tokens a `%%footer` template may use.  `$d` is a second spelling of `$D`.
    private static let footerPlaceholders: Set<Character> = ["P", "T", "D", "d"]

    /// Warns about every other `$`-token in a `%%footer` template (issue #141).
    ///
    /// The renderer substitutes `footerPlaceholders` and leaves the rest of the template in
    /// the literal text, so `%%footer "$X"` engraves the characters `$X` — and under the
    /// default `TextRendering.outlines` it engraves them as artwork, which nothing downstream
    /// can read back.  Parse time is the only place anyone gets told.  This catches both an
    /// abcm2ps placeholder CeolKit does not implement (`$F`, `$V`, `$P0`) and a typo such as
    /// `$p`; a `$` not followed by a letter (`$5`, a trailing `$`) is ordinary text, and
    /// `${name}` is a consumer-substitutable span, so neither is a token at all.
    ///
    /// One warning per distinct token: every occurrence shares the directive's source range,
    /// so repeating them would be noise pointing at the same line.
    private func diagnoseFooterPlaceholders(_ template: String, source: SourceRange,
                                            into diagnostics: inout [Diagnostic]) {
        var seen: Set<Character> = []
        for match in template.matches(of: /\$([A-Za-z])/) {
            guard let token = match.1.first,
                  !Self.footerPlaceholders.contains(token),
                  seen.insert(token).inserted else { continue }
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: .unknownFooterPlaceholder,
                message: "'$\(token)' is not a footer placeholder; it will be engraved literally",
                source: source,
                hint: "CeolKit substitutes $P, $T, $D and $d in %%footer."
            ))
        }
    }

    // Strips a single pair of surrounding double-quotes (e.g. `"text"` → `text`).
    private func stripQuotes(_ s: String) -> String {
        guard s.count >= 2, s.first == "\"", s.last == "\"" else { return s }
        return String(s.dropFirst().dropLast())
    }

    // Parses an ABC v2.2 <logical> value: "0"/"false" → false, "1"/"true" → true.
    private func parseLogical(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "0", "false": return false
        case "1", "true":  return true
        default:           return nil
        }
    }

    // MARK: - Voice building

    private func buildVoices(_ bodyCtx: BodyContext, tuneSource: SourceRange) -> ([Voice], [Diagnostic]) {
        var voices: [Voice] = []
        var diagnostics: [Diagnostic] = []

        for (voiceId, state) in bodyCtx.orderedVoices() {
            // A voice a `V:` declared and no music reached: it exists, with one empty stave,
            // so a later `%%score` can place it.  Renderers skip it — see `Voice.isEmpty`.
            var staves: [Staff] = []
            if let state {
                let accumulator = state.accumulator
                var (measures, voiceDiags) = finaliseAccumulator(accumulator, openingMeter: bodyCtx.openingMeter)
                diagnostics += voiceDiags

                // §7.4: each `&` layer of this voice, finished the same way and then squared
                // off against it, so a stave and its overlays hold the same bars.
                var layers: [(source: SourceRange, measures: [Measure])] = []
                for overlay in bodyCtx.overlays(of: voiceId) {
                    let (overlayMeasures, overlayDiags) =
                        finaliseAccumulator(overlay.state.accumulator, openingMeter: bodyCtx.openingMeter)
                    diagnostics += overlayDiags
                    layers.append((overlay.source, overlayMeasures))
                }
                let barsWritten = measures.count
                diagnostics += reconcileOverlays(
                    &measures, with: &layers, voiceId: voiceId,
                    unitNoteLength: accumulator.effectiveUnitNoteLength)
                // An overlay that overran gives the voice bars past the end of its last line.
                // They are that line's — the source wrote them there — so the boundary
                // recorded at what used to be the end is no longer a boundary at all.
                let breaks = measures.count > barsWritten
                    ? accumulator.staveBreaks.filter { $0.measureIndex < barsWritten }
                    : accumulator.staveBreaks

                var start = 0
                func appendStaff(through end: Int, evenIfEmpty: Bool = false) {
                    let slice = Array(measures[start..<end])
                    guard evenIfEmpty || !slice.isEmpty || (staves.isEmpty && end == measures.count)
                    else { return }
                    staves.append(Staff(
                        measures: slice,
                        overlays: layers.map {
                            VoiceOverlay(measures: Array($0.measures[start..<end]),
                                         source: $0.source)
                        }))
                }
                // An empty stave is kept, where an ordinary break that closed no measures is
                // not: it is a line-set the source wrote no line for in this voice, and
                // dropping it would shift every stave after it up one (#102).
                for brk in breaks where brk.measureIndex <= measures.count {
                    appendStaff(through: brk.measureIndex, evenIfEmpty: brk.isEmptyStave)
                    start = brk.measureIndex
                }
                appendStaff(through: measures.count)
            } else {
                staves = [Staff(measures: [], overlays: [])]
            }

            let props = foldingKeyClef(
                into: bodyCtx.voiceProperties[voiceId] ?? defaultVoiceProperties(),
                openingKey: state?.openingKey, tuneKey: bodyCtx.key)
            let vid: VoiceId = .named(voiceId)
            let voiceDirs = bodyCtx.voiceDirectives[voiceId] ?? []
            let voice = Voice(
                id: vid,
                properties: props,
                key: state?.openingKey,
                unitNoteLength: state?.openingUnitNoteLength,
                staves: staves,
                directives: voiceDirs,
                source: tuneSource
            )
            voices.append(voice)
        }
        if voices.isEmpty {
            // No events at all — return a single empty voice
            voices.append(Voice(
                id: .named("1"),
                properties: foldingKeyClef(into: defaultVoiceProperties(),
                                           openingKey: nil, tuneKey: bodyCtx.key),
                staves: [Staff(measures: [], overlays: [])],
                directives: [],
                source: tuneSource
            ))
        }
        return (voices, diagnostics)
    }

    /// Squares a voice's `&` layers off against the voice itself, so every layer holds
    /// exactly one measure per measure of the voice (§7.4, and see ``VoiceOverlay``).
    ///
    /// A layer that says nothing in a bar gets an empty measure there; the merge draws
    /// nothing from it and the voice underneath keeps the bar's furniture.  A layer that runs
    /// *past* the voice is the standard's "one complete bar's worth of music for each `&`"
    /// broken: the voice is given the bars it is missing and a warning says so, because the
    /// alternative is dropping bars the author wrote.
    private func reconcileOverlays(
        _ measures: inout [Measure],
        with layers: inout [(source: SourceRange, measures: [Measure])],
        voiceId: String,
        unitNoteLength: Fraction
    ) -> [Diagnostic] {
        guard !layers.isEmpty else { return [] }
        var diagnostics: [Diagnostic] = []

        for layer in layers where layer.measures.count > measures.count {
            diagnostics.append(Diagnostic(
                severity: .warning, code: .voiceOverlayTooLong,
                message: "the & overlay in voice \(voiceId) has \(layer.measures.count) bars "
                       + "where the music it overlays has \(measures.count); §7.4 allows one "
                       + "bar for each &. The extra bars are printed, and the voice under them "
                       + "is left empty.",
                source: layer.source,
                hint: "write one & for each bar the overlay covers, or close the overlay with "
                    + "a bar line before the extra music."))
        }

        let width = max(measures.count, layers.map(\.measures.count).max() ?? 0)
        let tail = measures.last
        let tailUnit = tail?.unitNoteLength ?? unitNoteLength
        measures += (measures.count..<width).map { _ in
            emptyMeasure(after: tail, unitNoteLength: tailUnit)
        }
        for index in layers.indices {
            let source = layers[index].source
            let layerUnit = layers[index].measures.last?.unitNoteLength ?? unitNoteLength
            layers[index].measures += (layers[index].measures.count..<width).map { _ in
                emptyMeasure(after: nil, unitNoteLength: layerUnit, at: source)
            }
        }
        return diagnostics
    }

    /// A bar with no music in it, for a voice or an overlay that has nothing to say here.
    ///
    /// `unitNoteLength` is the one in force where the bar is being added: the last real
    /// measure's, or the voice's own where there is no real measure to follow.
    private func emptyMeasure(after previous: Measure?, unitNoteLength: Fraction,
                              at source: SourceRange? = nil) -> Measure {
        let src = source ?? previous?.source ?? .emptySourceRange
        return Measure(openingBar: previous?.closingBar,
                       events: [],
                       closingBar: BarLine(kind: .single, source: src),
                       endingNumber: nil,
                       source: src,
                       meter: nil,
                       unitNoteLength: unitNoteLength)
    }

    /// Closes a voice out into measures: the last open bar, tie resolution across the whole
    /// voice, and beaming.
    ///
    /// `openingMeter` is the meter the voice's *first* measure is in, not the one the body
    /// ended in.  Meter and unit note length both move part way through a tune, and every
    /// measure knows which it is in — `Measure.meter` where the meter moved, and
    /// `Measure.unitNoteLength` always — so the beams are grouped measure by measure against
    /// whatever was in force there (#85, #122).
    private func finaliseAccumulator(
        _ acc: VoiceAccumulator, openingMeter: Meter
    ) -> ([Measure], [Diagnostic]) {
        var measures = acc.closedMeasures
        var diagnostics: [Diagnostic] = []

        // Close the final open measure if it holds music.  Spacer-only content is not music
        // and not a measure — `closeWith` says the same at every bar line, and the leading
        // whitespace of an `&` continuation line would otherwise close a bar of nothing.
        if acc.hasOpenMeasure {
            let finalBar = BarLine(
                kind: .final,
                source: acc.currentEvents.reversed().lazy
                    .compactMap(eventSourceRange).first ?? .emptySourceRange
            )
            let src = measureSourceSpan(
                events: acc.currentEvents,
                openingBar: acc.lastBarLine,
                closingBar: finalBar,
                fallback: acc.measureSource
            )
            // An `L:` still pending at the end of the voice lands on this bar exactly where
            // `closeWith` would have put it: on the bar the music after it fell in.
            var finalUnit = acc.effectiveUnitNoteLength
            if let change = acc.pendingUnitNoteLength, acc.musicalEventCount > change.after {
                finalUnit = change.length
            }
            // A `K:` still pending lands here on the same terms, so a key stated in the last
            // bar of a voice is still engraved where it happens.
            var finalKey: KeySignature? = nil
            if let change = acc.pendingKey, acc.musicalEventCount > change.after {
                finalKey = change.key
            }
            let finalMeasure = Measure(
                openingBar: acc.lastBarLine,
                events: acc.currentEvents,
                closingBar: finalBar,
                endingNumber: nil,
                source: src,
                meter: acc.pendingMeter,
                key: finalKey,
                unitNoteLength: finalUnit
            )
            measures.append(finalMeasure)
        }

        // Apply tie resolution across all events (ties can span bar lines)
        let allEvents = measures.flatMap { $0.events }
        let tieResolved = TieResolver().resolve(allEvents)

        // Detect dangling ties: any note with .startsTie that has no successor with .endsTie/.continuesTie
        var tieStarts: [(step: DiatonicStep, octave: Int, source: SourceRange)] = []
        for event in tieResolved {
            if case .note(let n) = event {
                switch n.ties {
                case .startsTie:
                    tieStarts.append((n.pitch.step, n.pitch.octave, n.source))
                case .endsTie, .continuesTie:
                    tieStarts.removeAll { $0.step == n.pitch.step && $0.octave == n.pitch.octave }
                case .none:
                    break
                }
            }
        }
        for dangling in tieStarts {
            diagnostics.append(Diagnostic(
                severity: .warning, code: .danglingTie,
                message: "Tie has no following note to connect to",
                source: dangling.source
            ))
        }

        // Re-partition tie-resolved events back into measures
        var offset = 0
        var resolvedMeasures: [Measure] = []
        for m in measures {
            let count = m.events.count
            let resolvedEvents = Array(tieResolved[offset..<(offset + count)])
            offset += count
            resolvedMeasures.append(Measure(
                openingBar: m.openingBar,
                events: resolvedEvents,
                closingBar: m.closingBar,
                endingNumber: m.endingNumber,
                endingStartIndex: m.endingStartIndex,
                source: m.source,
                meter: m.meter,
                key: m.key,
                unitNoteLength: m.unitNoteLength
            ))
        }

        // Beam measure by measure, against the meter and unit note length in force *there*.
        // Both start at what the voice opened in; the meter moves where a measure records a
        // change and the unit note length wherever a measure differs from the last.  A tune
        // that changes neither builds one resolver and uses it throughout.
        var currentMeter = openingMeter
        var currentUnit = acc.openingUnitNoteLength
        var resolver = BeamResolver(meter: currentMeter, unitNoteLength: currentUnit)
        var beamResolved: [Measure] = []
        beamResolved.reserveCapacity(resolvedMeasures.count)
        for m in resolvedMeasures {
            if m.meter != nil || m.unitNoteLength != currentUnit {
                currentMeter = m.meter ?? currentMeter
                currentUnit = m.unitNoteLength
                resolver = BeamResolver(meter: currentMeter, unitNoteLength: currentUnit)
            }
            beamResolved.append(Measure(
                openingBar: m.openingBar,
                events: resolver.resolve(m.events),
                closingBar: m.closingBar,
                endingNumber: m.endingNumber,
                endingStartIndex: m.endingStartIndex,
                source: m.source,
                meter: m.meter,
                key: m.key,
                unitNoteLength: m.unitNoteLength
            ))
        }
        return (beamResolved, diagnostics)
    }

    /// Folds a `K:` clef into a voice's properties, so the renderer keeps reading one place.
    ///
    /// §4.6 lets `clef=` be written on `K:` as well as on `V:`, and the two have to be
    /// reconciled somewhere.  The `V:` wins: it names the staff, and the key field's clef is
    /// the older spelling of the same thing.  Where the voice named no clef, the clef comes
    /// from the key the voice opens in — its own `K:` — and failing that from the tune's,
    /// because a clef set on the tune's key holds until something else changes it.
    ///
    /// Neither field can say "no clef" — both parsers resolve an absent `clef=` to treble —
    /// so a stated treble reads here as silence.  Nothing is lost by that: the fallback it
    /// suppresses can only put treble back.
    ///
    /// A `K:` part way through a voice is not considered: `openingKey` is only the key of a
    /// `K:` that arrives before the voice's first note, and the renderer has one clef per
    /// voice for the whole tune, so a mid-tune change has nowhere to go yet (#126).
    private func foldingKeyClef(
        into props: VoiceProperties,
        openingKey: KeySignature?,
        tuneKey: KeySignature
    ) -> VoiceProperties {
        let defaultClef = ClefSpec(clef: .treble, octaveShift: 0)
        guard props.clef == defaultClef else { return props }
        let candidates = [openingKey?.clef, tuneKey.clef]
        guard let keyClef = candidates.compactMap({ $0 }).first(where: { $0 != defaultClef })
        else { return props }
        return VoiceProperties(
            clef: keyClef,
            transposition: props.transposition,
            staffProperties: props.staffProperties,
            name: props.name,
            subname: props.subname,
            stemDirection: props.stemDirection,
            middleNote: props.middleNote
        )
    }

    private func defaultVoiceProperties() -> VoiceProperties {
        VoiceProperties(
            clef: ClefSpec(clef: .treble, octaveShift: 0),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: 5),
            name: nil,
            subname: nil,
            stemDirection: .auto,
            middleNote: nil
        )
    }

    private func buildMetadata(_ ctx: TuneContext) -> TuneMetadata {
        TuneMetadata(
            composer: ctx.composer,
            origin: ctx.origins,
            area: ctx.area,
            book: ctx.book,
            discography: ctx.discography,
            fileURL: ctx.fileURL,
            group: ctx.group,
            history: ctx.history,
            notes: ctx.notes,
            source: ctx.sourceText,
            rhythm: ctx.rhythm,
            transcription: ctx.transcription
        )
    }
}

// MARK: - TuneContext

/// Accumulates header fields for one ABCTune.
private struct TuneContext {
    var reference: Int? = nil
    var titles: [TextString] = []
    var key: KeySignature? = nil
    var meter: Meter? = nil
    var unitNoteLength: Fraction? = nil
    var tempo: Tempo? = nil
    var parts: PartPlan? = nil
    var headerVoices: [String: VoiceProperties] = [:]
    /// The ids of `headerVoices` in the order the header declared them.  The dictionary
    /// answers "what are this voice's properties?"; this answers "in what order do the
    /// voices print?", which a dictionary cannot (issue #61).
    var headerVoiceOrder: [String] = []
    var userSymbols: [Character: Decoration] = [:]
    var macros: [MacroDefinition] = []
    // metadata fields
    var composer: TextString? = nil
    var origins: [String] = []
    var area: TextString? = nil
    var book: TextString? = nil
    var discography: TextString? = nil
    var fileURL: URL? = nil
    var group: TextString? = nil
    var history: [TextString] = []
    var notes: TextString? = nil
    var sourceText: TextString? = nil
    var rhythm: TextString? = nil
    var transcription: TextString? = nil
    // I:linebreak parsed per ABC 2.2 §9.2 — default is I:linebreak <EOL> $
    var linebreakChars: Set<Character> = ["$"] // $ and/or !
    var linebreakOnEOL: Bool = true            // <EOL> token
}

// MARK: - Orientation requests

/// A `%%landscape` and the point in the tune it was written at, before it is paired with the
/// `%%newpage` that gives it a page boundary to take effect at (issue #158).
struct OrientationRequest {
    /// `true` for `%%landscape 1`, `false` for `%%landscape 0`.
    let landscape: Bool
    /// The stave the directive stands in front of, in the tune's own numbering — the same
    /// unit ``PageBreak/beforeStave`` counts in.  A directive in the gap above a tune or in
    /// its header is 0; one in the body is the stave enclosing it.
    let stave: Int
    let source: SourceRange
}
