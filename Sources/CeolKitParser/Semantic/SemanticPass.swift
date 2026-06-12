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
        var currentFooter: String? = nil
        for line in file.filePreamble {
            if case .directive(let name, let payload, let src) = line {
                if name == "footer" {
                    currentFooter = stripQuotes(payload.trimmingCharacters(in: .whitespaces))
                } else if isCeolKitDirective(name) || isStandardDirective(name) {
                    var tempDiags: [Diagnostic] = []
                    if let d = parseCeolKitDirective(name: name, payload: payload, source: src, diagnostics: &tempDiags) {
                        preambleCeolKitDirectives.append(
                            CeolKitDirectiveScope(directive: d, scope: .tuneGlobal, source: src)
                        )
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
        }

        let dialect: Dialect
        if let override = options.dialectOverride {
            dialect = override
        } else if let v = file.versionLine {
            dialect = .strict(version: v)
        } else {
            dialect = dialectHint ?? .loose
        }

        let fileSource = file.tunes.first?.source ?? emptySource

        var tunes: [Tune] = []
        for (idx, abcTune) in file.tunes.enumerated() {
            // Update footer from tune header directives (last-wins across document).
            for (name, payload, _) in abcTune.headerDirectives where name == "footer" {
                currentFooter = stripQuotes(payload.trimmingCharacters(in: .whitespaces))
            }
            let (tune, tuneDiags) = buildTune(abcTune, dialect: dialect)
            diagnostics += tuneDiags
            if idx == 0 && !preambleCeolKitDirectives.isEmpty {
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
                    directives: preambleCeolKitDirectives + tune.directives,
                    source: tune.source
                ))
            } else {
                tunes.append(tune)
            }
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
            footer: currentFooter,
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
        name == "landscape" || name == "flatbeams" || name == "titleformat" || name == "footer"
    }

    // MARK: - Tune builder

    private func buildTune(_ abcTune: ABCTune, dialect: Dialect) -> (Tune, [Diagnostic]) {
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
            macros: ctx.macros,
            headerVoices: ctx.headerVoices,
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
            source: abcTune.source
        )
        return (tune, diagnostics)
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
        case .voice(let id, let props, _): ctx.headerVoices[id] = props
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
        for line in body {
            // Check if this is a single-field lyric line
            if line.count == 1, case .inlineField(let f, _) = line[0], case .lyric(let tokens, _) = f {
                ctx.applyLyrics(tokens)
                continue
            }
            // Record lyric anchor before processing this music line
            for id in ctx.voiceOrder {
                ctx.lyricMeasureAnchor[id] = ctx.voiceData[id]?.closedMeasures.count ?? 0
            }
            ctx.lyricMeasureAnchor[ctx.currentVoiceId] =
                ctx.voiceData[ctx.currentVoiceId]?.closedMeasures.count ?? 0
            walkLine(line, ctx: &ctx, diagnostics: &diagnostics)
            if ctx.linebreakOnEOL {
                ctx.splitCurrentStave()
            }
        }
    }

    private func walkLine(
        _ elements: [MusicElement],
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        // Pre-pass: resolve broken rhythms so note durations are correct
        let resolved = resolveBrokenRhythms(elements)

        for elem in resolved {
            walkElement(elem, ctx: &ctx, diagnostics: &diagnostics)
        }
        // Finish any open grace group (malformed; just close it)
        if ctx.inGrace {
            ctx.flushGrace()
        }
    }

    private func walkElement(
        _ elem: MusicElement,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        let prevWasSpace = ctx.lastElementWasSpace
        ctx.lastElementWasSpace = false

        switch elem {
        case .note(let tok):
            let event = buildNoteEvent(tok, ctx: &ctx)
            ctx.emit(event)

        case .chord(let notes, let src):
            let event = buildChordEvent(notes, source: src, ctx: &ctx)
            ctx.emit(event)

        case .rest(let kind, let dur, let src):
            let duration = resolveDuration(dur)
            let rest = Rest(kind: kind, duration: duration, decorations: ctx.flushDecorations(), source: src)
            ctx.emit(.rest(rest))

        case .barLine(let kind, let src):
            ctx.closeCurrentMeasure(barLine: BarLine(kind: kind, source: src))
            ctx.accidentalScope.resetBar()

        case .inlineField(let field, let src):
            applyInlineField(field, source: src, ctx: &ctx, diagnostics: &diagnostics)

        case .graceStart(let acciaccatura, _):
            ctx.startGrace(acciaccatura: acciaccatura)

        case .graceEnd(let src):
            ctx.flushGrace(source: src)

        case .decoration(let tok, _):
            let decoration = expandDecoration(tok, userSymbols: ctx.userSymbols)
            // Post-note decoration: if preceded by a space and there's a note in currentEvents,
            // apply retroactively to the preceding note.
            if prevWasSpace && ctx.applyDecorationToLastNote(decoration) {
                // Applied retroactively
            } else {
                ctx.pendingDecorations.append(decoration)
            }

        case .annotation(let pos, let text, let src):
            ctx.pendingAnnotations.append(Annotation(
                position: pos,
                text: TextString(value: text, source: src),
                source: src
            ))

        case .chordSymbol(let s, let src):
            ctx.pendingChordSymbol = parseChordSymbol(s, source: src)

        case .tupletStart(let p, let q, let r, let src):
            let resolvedQ = q ?? defaultQ(p: p, meter: ctx.meter)
            let resolvedR = r ?? p
            ctx.startTuplet(p: p, q: resolvedQ, r: resolvedR, source: src)

        case .slurOpen:
            ctx.openSlurs += 1

        case .slurClose:
            ctx.closeSlurs += 1

        case .endingNumber(let nums, _):
            ctx.pendingEndingNumber = nums

        case .space:
            ctx.emitSpaceBreak()
            ctx.lastElementWasSpace = true

        case .brokenRhythm:
            break  // already handled in resolveBrokenRhythms pre-pass

        case .unknown(let ch, let src):
            if ctx.linebreakChars.contains(ch) {
                ctx.splitCurrentStave()
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

    private func buildNoteEvent(_ tok: NoteToken, ctx: inout BodyContext) -> Event {
        let step = diatonicStep(from: tok.pitchLetter)
        // ABC octave convention: uppercase C..B = octave 4 (middle C = C4), lowercase c..b = octave 5
        let baseOctave = tok.pitchLetter.isUppercase ? 4 : 5
        let octave = baseOctave + tok.octaveMarks

        let currentResolved = ctx.accidentalScope.resolve(step: step, octave: octave)
        let writtenAlt = tok.accidental.map { alterationFromToken($0) }
        let playedAlt: Alteration
        let displayedAlt: Alteration?
        if let written = writtenAlt {
            playedAlt = written
            // displayedAccidental is nil when the accidental is redundant (bar memory already implies it)
            displayedAlt = (written == currentResolved) ? nil : written
            ctx.accidentalScope.record(step: step, octave: octave, alteration: written)
        } else {
            playedAlt = currentResolved
            displayedAlt = nil
        }

        let pitch = Pitch(step: step, alteration: playedAlt, octave: octave)
        let duration = resolveDuration(tok.duration)
        let tieState: TieState = tok.tie ? .startsTie : .none
        let (opens, closes) = ctx.consumeSlurs()

        let note = Note(
            pitch: pitch,
            writtenAccidental: writtenAlt,
            displayedAccidental: displayedAlt,
            duration: duration,
            ties: tieState,
            slurs: SlurState(opens: opens, closes: closes),
            decorations: ctx.flushDecorations(),
            chordSymbol: ctx.flushChordSymbol(),
            annotations: ctx.flushAnnotations(),
            beam: .single,
            lyric: nil,
            source: tok.source
        )

        if ctx.inGrace {
            ctx.graceNotes.append(note)
            return .note(note)  // returned but not emitted directly; grace buffer holds it
        }
        if ctx.tupletState != nil {
            return .note(note)  // will be handed to tuplet collector
        }
        return .note(note)
    }

    private func buildChordEvent(_ notes: [NoteToken], source: SourceRange, ctx: inout BodyContext) -> Event {
        let resolvedNotes: [Note] = notes.map { tok in
            let step = diatonicStep(from: tok.pitchLetter)
            let baseOctave = tok.pitchLetter.isUppercase ? 4 : 5
            let octave = baseOctave + tok.octaveMarks

            let currentResolved = ctx.accidentalScope.resolve(step: step, octave: octave)
            let writtenAlt = tok.accidental.map { alterationFromToken($0) }
            let playedAlt: Alteration
            let displayedAlt: Alteration?
            if let written = writtenAlt {
                playedAlt = written
                displayedAlt = (written == currentResolved) ? nil : written
                ctx.accidentalScope.record(step: step, octave: octave, alteration: written)
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
        let (opens, closes) = ctx.consumeSlurs()

        let chord = Chord(
            notes: resolvedNotes,
            duration: duration,
            decorations: ctx.flushDecorations(),
            chordSymbol: ctx.flushChordSymbol(),
            annotations: ctx.flushAnnotations(),
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
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        switch field {
        case .key(let k):
            ctx.key = k
            ctx.accidentalScope = AccidentalScope(keyAlterations: keyAlterations(for: k))
        case .meter(let m, _):
            ctx.meter = m
        case .unitNoteLength(let f, _):
            ctx.unitNoteLength = f
        case .tempo:
            break  // tempo changes not tracked per-voice in v0.1
        case .voice(let id, let props, _):
            ctx.switchVoice(id: id, properties: props)
        case .lyric(let tokens, _):
            ctx.applyLyrics(tokens)
        case .userSymbol(let ch, let dec, _):
            ctx.userSymbols[ch] = dec
        case .unknown(let code, let payload, let src) where String(code) == "%":
            // Body-level directive stored by ABCFileBuilder as .unknown(code:"%", payload:"name payload")
            let parts = payload.split(separator: " ", maxSplits: 1)
            let dirName = parts.first.map(String.init) ?? payload
            let dirPayload = parts.count > 1 ? String(parts[1]) : ""
            applyBodyDirective(name: dirName, payload: dirPayload, source: src, ctx: &ctx, diagnostics: &diagnostics)
        default:
            break
        }
    }

    private func applyBodyDirective(
        name: String,
        payload: String,
        source: SourceRange,
        ctx: inout BodyContext,
        diagnostics: inout [Diagnostic]
    ) {
        switch name {
        case "ceolkit:stemalignment":
            if ctx.hasExplicitVoice {
                var tempDiags: [Diagnostic] = []
                if let d = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &tempDiags) {
                    let vid = VoiceId.named(ctx.currentVoiceId)
                    let scope = Scope.voiceLocal(vid)
                    ctx.voiceDirectives[ctx.currentVoiceId, default: []].append(
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
        case "landscape", "flatbeams", "ceolkit:justifylast", "titleformat", "footer":
            var tempDiags: [Diagnostic] = []
            if let d = parseCeolKitDirective(name: name, payload: payload, source: source, diagnostics: &tempDiags) {
                ctx.bodyTuneDirectives.append(CeolKitDirectiveScope(directive: d, scope: .tuneGlobal, source: source))
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

    private func reducedFraction(numerator: Int, denominator: Int) -> Fraction {
        guard numerator != 0 else { return Fraction(numerator: 0, denominator: 1) }
        let g = gcd(abs(numerator), abs(denominator))
        return Fraction(numerator: numerator / g, denominator: denominator / g)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

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
            staffProperties: StaffProperties(staffLines: 5, scale: nil),
            source: source
        )
    }

    private var emptySource: SourceRange {
        SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
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
        case "titleformat":
            return .titleFormat(trimmed)
        case "footer":
            // %%footer is file-scoped and extracted directly in build(); silently accept here.
            return nil
        default:
            return nil
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

        for (voiceId, accumulator) in bodyCtx.voices(orderedBy: bodyCtx.voiceOrder) {
            let (measures, voiceDiags) = finaliseAccumulator(accumulator, meter: bodyCtx.meter)
            diagnostics += voiceDiags

            var staves: [Staff] = []
            var start = 0
            for breakIdx in accumulator.staveBreakIndices where breakIdx <= measures.count {
                let slice = Array(measures[start..<breakIdx])
                if !slice.isEmpty {
                    staves.append(Staff(measures: slice, overlays: []))
                }
                start = breakIdx
            }
            let tail = Array(measures[start...])
            if !tail.isEmpty || staves.isEmpty {
                staves.append(Staff(measures: tail, overlays: []))
            }

            let props = bodyCtx.voiceProperties[voiceId] ?? defaultVoiceProperties()
            let vid: VoiceId = .named(voiceId)
            let voiceDirs = bodyCtx.voiceDirectives[voiceId] ?? []
            let voice = Voice(
                id: vid,
                properties: props,
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
                properties: defaultVoiceProperties(),
                staves: [Staff(measures: [], overlays: [])],
                directives: [],
                source: tuneSource
            ))
        }
        return (voices, diagnostics)
    }

    private func finaliseAccumulator(_ acc: VoiceAccumulator, meter: Meter) -> ([Measure], [Diagnostic]) {
        var measures = acc.closedMeasures
        var diagnostics: [Diagnostic] = []

        // Close the final open measure if it has events
        if !acc.currentEvents.isEmpty {
            let finalBar = BarLine(
                kind: .final,
                source: acc.currentEvents.last.flatMap { eventSource($0) } ?? emptySource
            )
            let src = acc.currentEvents.first.flatMap { eventSource($0) } ?? emptySource
            let finalMeasure = Measure(
                openingBar: acc.lastBarLine,
                events: acc.currentEvents,
                closingBar: finalBar,
                endingNumber: nil,
                source: src
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
                source: m.source
            ))
        }

        // Apply beam resolution to all measures
        let resolver = BeamResolver(meter: meter, unitNoteLength: acc.unitNoteLength)
        let beamResolved = resolvedMeasures.map { m in
            Measure(
                openingBar: m.openingBar,
                events: resolver.resolve(m.events),
                closingBar: m.closingBar,
                endingNumber: m.endingNumber,
                source: m.source
            )
        }
        return (beamResolved, diagnostics)
    }

    private func eventSource(_ event: Event) -> SourceRange? {
        switch event {
        case .note(let n): return n.source
        case .rest(let r): return r.source
        case .chord(let c): return c.source
        case .grace(let g): return g.source
        case .tuplet(let t): return t.source
        case .spacer(let s): return s.source
        case .directiveAnchor: return nil
        }
    }

    private func defaultVoiceProperties() -> VoiceProperties {
        VoiceProperties(
            clef: ClefSpec(clef: .treble, octaveShift: 0),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: 5, scale: nil),
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
    // I:linebreak parsed per ABC 2.2 §9.2
    var linebreakChars: Set<Character> = []   // $ and/or !
    var linebreakOnEOL: Bool = false           // <EOL> token
}

// MARK: - VoiceAccumulator

struct VoiceAccumulator {
    var closedMeasures: [Measure] = []
    var staveBreakIndices: [Int] = []
    var currentEvents: [Event] = []
    var lastBarLine: BarLine? = nil
    var measureSource: SourceRange
    var unitNoteLength: Fraction

    init(source: SourceRange, unitNoteLength: Fraction) {
        self.measureSource = source
        self.unitNoteLength = unitNoteLength
    }

    mutating func markStaveBoundary() {
        let idx = closedMeasures.count
        guard idx != staveBreakIndices.last else { return }  // no new measures since last split
        staveBreakIndices.append(idx)
    }

    mutating func closeWith(barLine: BarLine, endingNumber: [Int]?) {
        // Skip spacer-only content (e.g. the space between [V:1] and |:) — treat as empty.
        let hasMusicalContent = currentEvents.contains {
            if case .spacer = $0 { return false }
            return true
        }
        guard hasMusicalContent || endingNumber != nil else {
            currentEvents = []
            lastBarLine = barLine
            return
        }
        let src = currentEvents.first.flatMap { eventSource($0) } ?? measureSource
        let measure = Measure(
            openingBar: lastBarLine,
            events: currentEvents,
            closingBar: barLine,
            endingNumber: endingNumber,
            source: src
        )
        closedMeasures.append(measure)
        currentEvents = []
        lastBarLine = barLine
    }

    private func eventSource(_ event: Event) -> SourceRange? {
        switch event {
        case .note(let n): return n.source
        case .rest(let r): return r.source
        case .chord(let c): return c.source
        case .grace(let g): return g.source
        case .tuplet(let t): return t.source
        case .spacer(let s): return s.source
        case .directiveAnchor: return nil
        }
    }
}

// MARK: - BodyContext

/// Mutable state threaded through music body processing.
private struct BodyContext {
    var unitNoteLength: Fraction
    var meter: Meter
    var key: KeySignature
    var userSymbols: [Character: Decoration]
    var macros: [MacroDefinition]
    var accidentalScope: AccidentalScope

    // Voice tracking
    var currentVoiceId: String = "1"
    var voiceOrder: [String] = ["1"]
    private(set) var voiceData: [String: VoiceAccumulator] = [:]
    var voiceProperties: [String: VoiceProperties] = [:]
    var voiceDirectives: [String: [CeolKitDirectiveScope]] = [:]
    var bodyTuneDirectives: [CeolKitDirectiveScope] = []
    var hasExplicitVoice: Bool = false

    // Pending attachments for the next note/chord
    var pendingDecorations: [Decoration] = []
    var pendingAnnotations: [Annotation] = []
    var pendingChordSymbol: ChordSymbol? = nil
    var pendingEndingNumber: [Int]? = nil

    // Slur state
    var openSlurs: Int = 0
    var closeSlurs: Int = 0

    // Grace group accumulation
    var inGrace: Bool = false
    var graceAcciaccatura: Bool = false
    var graceNotes: [Note] = []
    var graceSource: SourceRange?

    // Tuplet state
    var tupletState: TupletState? = nil

    // Lyric anchor: closedMeasures count before the current music line (per voice)
    var lyricMeasureAnchor: [String: Int] = [:]

    // Space tracking for post-note decoration
    var lastElementWasSpace: Bool = false

    // I:linebreak settings — ABC 2.2 §9.2 closed vocabulary
    var linebreakChars: Set<Character> = []   // $ and/or !
    var linebreakOnEOL: Bool = false           // <EOL>

    init(
        unitNoteLength: Fraction,
        meter: Meter,
        key: KeySignature,
        userSymbols: [Character: Decoration],
        macros: [MacroDefinition],
        headerVoices: [String: VoiceProperties] = [:],
        linebreakChars: Set<Character> = [],
        linebreakOnEOL: Bool = false
    ) {
        self.unitNoteLength = unitNoteLength
        self.meter = meter
        self.key = key
        self.userSymbols = userSymbols
        self.macros = macros
        self.accidentalScope = AccidentalScope(keyAlterations: keyAlterations(for: key))
        self.voiceProperties = headerVoices
        self.linebreakChars = linebreakChars
        self.linebreakOnEOL = linebreakOnEOL
    }

    mutating func splitCurrentStave() {
        voiceData[currentVoiceId]?.markStaveBoundary()
    }

    // Returns voices in the order they were first encountered.
    func voices(orderedBy order: [String]) -> [(String, VoiceAccumulator)] {
        order.compactMap { id in voiceData[id].map { (id, $0) } }
    }

    mutating func currentAccumulator() -> VoiceAccumulator {
        if voiceData[currentVoiceId] == nil {
            let src = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
            voiceData[currentVoiceId] = VoiceAccumulator(source: src, unitNoteLength: unitNoteLength)
        }
        return voiceData[currentVoiceId]!
    }

    mutating func emit(_ event: Event) {
        if inGrace {
            // Grace notes are accumulated; the note itself was already added to graceNotes
            return
        }
        if var tuplet = tupletState {
            tuplet.events.append(event)
            tupletState = tuplet
            if tuplet.events.count >= tuplet.r {
                flushTuplet()
            }
            return
        }
        voiceData[currentVoiceId, default: VoiceAccumulator(
            source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1),
            unitNoteLength: unitNoteLength
        )].currentEvents.append(event)
    }

    mutating func emitSpaceBreak() {
        let src = SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
        emit(.spacer(Spacer(width: 0, source: src)))
    }

    mutating func closeCurrentMeasure(barLine: BarLine) {
        voiceData[currentVoiceId, default: VoiceAccumulator(
            source: SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1),
            unitNoteLength: unitNoteLength
        )].closeWith(barLine: barLine, endingNumber: pendingEndingNumber)
        pendingEndingNumber = nil
    }

    mutating func switchVoice(id: String, properties: VoiceProperties) {
        if !voiceOrder.contains(id) { voiceOrder.append(id) }
        currentVoiceId = id
        hasExplicitVoice = true

        let defaultClef = ClefSpec(clef: .treble, octaveShift: 0)

        if let existing = voiceProperties[id] {
            // Merge: only override with non-default values from new properties,
            // preserving header-set values when inline V: uses defaults.
            voiceProperties[id] = VoiceProperties(
                clef: properties.clef != defaultClef ? properties.clef : existing.clef,
                transposition: properties.transposition != .none ? properties.transposition : existing.transposition,
                staffProperties: (properties.staffProperties.staffLines != 5 || properties.staffProperties.scale != nil)
                    ? properties.staffProperties : existing.staffProperties,
                name: properties.name ?? existing.name,
                subname: properties.subname ?? existing.subname,
                stemDirection: properties.stemDirection != .auto ? properties.stemDirection : existing.stemDirection,
                middleNote: properties.middleNote ?? existing.middleNote
            )
        } else {
            voiceProperties[id] = properties
        }
    }

    mutating func startGrace(acciaccatura: Bool) {
        inGrace = true
        graceAcciaccatura = acciaccatura
        graceNotes = []
    }

    mutating func flushGrace(source: SourceRange? = nil) {
        let src = source ?? graceSource ?? SourceRange(file: nil, byteOffset: 0, length: 0, line: 1, column: 1)
        let kind: GraceKind = graceAcciaccatura ? .acciaccatura : .appoggiatura
        let group = GraceGroup(kind: kind, notes: graceNotes, source: src)
        inGrace = false
        graceNotes = []
        graceAcciaccatura = false
        voiceData[currentVoiceId, default: VoiceAccumulator(
            source: src, unitNoteLength: unitNoteLength
        )].currentEvents.append(.grace(group))
    }

    mutating func startTuplet(p: Int, q: Int, r: Int, source: SourceRange) {
        tupletState = TupletState(p: p, q: q, r: r, source: source)
    }

    mutating func flushTuplet() {
        guard let tuplet = tupletState else { return }
        let adjustedEvents = tuplet.events.map { applyTupletFactor(q: tuplet.q, p: tuplet.p, to: $0) }
        let t = Tuplet(p: tuplet.p, q: tuplet.q, r: tuplet.r, events: adjustedEvents, source: tuplet.source)
        tupletState = nil
        voiceData[currentVoiceId, default: VoiceAccumulator(
            source: tuplet.source, unitNoteLength: unitNoteLength
        )].currentEvents.append(.tuplet(t))
    }

    /// Applies lyrics to events from the music line just before this lyric field.
    /// Uses lyricMeasureAnchor to find which closed measures belong to the preceding line.
    mutating func applyLyrics(_ tokens: [LyricToken]) {
        guard var acc = voiceData[currentVoiceId] else { return }
        let anchor = lyricMeasureAnchor[currentVoiceId] ?? 0

        // Collect all events from closedMeasures[anchor...] + currentEvents
        var allEvents: [Event] = []
        for i in anchor..<acc.closedMeasures.count {
            allEvents += acc.closedMeasures[i].events
        }
        allEvents += acc.currentEvents

        let aligned = LyricAligner.align(tokens: tokens, to: allEvents)

        // Write back: first update closedMeasures[anchor...], then currentEvents
        var offset = 0
        for i in anchor..<acc.closedMeasures.count {
            let count = acc.closedMeasures[i].events.count
            let newEvents = Array(aligned[offset..<(offset + count)])
            acc.closedMeasures[i] = Measure(
                openingBar: acc.closedMeasures[i].openingBar,
                events: newEvents,
                closingBar: acc.closedMeasures[i].closingBar,
                endingNumber: acc.closedMeasures[i].endingNumber,
                source: acc.closedMeasures[i].source
            )
            offset += count
        }
        acc.currentEvents = Array(aligned[offset...])
        voiceData[currentVoiceId] = acc
    }

    /// Retroactively applies a decoration to the last note in currentEvents (skipping spacers).
    /// Returns true if successfully applied.
    mutating func applyDecorationToLastNote(_ decoration: Decoration) -> Bool {
        guard var acc = voiceData[currentVoiceId] else { return false }
        for i in stride(from: acc.currentEvents.count - 1, through: 0, by: -1) {
            switch acc.currentEvents[i] {
            case .spacer:
                continue
            case .note(let n):
                acc.currentEvents[i] = .note(Note(
                    pitch: n.pitch,
                    writtenAccidental: n.writtenAccidental,
                    displayedAccidental: n.displayedAccidental,
                    duration: n.duration,
                    ties: n.ties,
                    slurs: n.slurs,
                    decorations: n.decorations + [decoration],
                    chordSymbol: n.chordSymbol,
                    annotations: n.annotations,
                    beam: n.beam,
                    lyric: n.lyric,
                    source: n.source
                ))
                voiceData[currentVoiceId] = acc
                return true
            default:
                return false
            }
        }
        return false
    }

    mutating func flushDecorations() -> [Decoration] {
        defer { pendingDecorations = [] }
        return pendingDecorations
    }

    mutating func flushAnnotations() -> [Annotation] {
        defer { pendingAnnotations = [] }
        return pendingAnnotations
    }

    mutating func flushChordSymbol() -> ChordSymbol? {
        defer { pendingChordSymbol = nil }
        return pendingChordSymbol
    }

    mutating func consumeSlurs() -> (opens: Int, closes: Int) {
        defer { openSlurs = 0; closeSlurs = 0 }
        return (openSlurs, closeSlurs)
    }
}

// MARK: - TupletState

private struct TupletState {
    let p: Int
    let q: Int
    let r: Int
    let source: SourceRange
    var events: [Event] = []
}

// MARK: - Tuplet duration adjustment

private func applyTupletFactor(q: Int, p: Int, to event: Event) -> Event {
    switch event {
    case .note(let n):
        let dur = reduceFraction(
            numerator: n.duration.numerator * q,
            denominator: n.duration.denominator * p
        )
        return .note(Note(
            pitch: n.pitch,
            writtenAccidental: n.writtenAccidental,
            displayedAccidental: n.displayedAccidental,
            duration: dur,
            ties: n.ties,
            slurs: n.slurs,
            decorations: n.decorations,
            chordSymbol: n.chordSymbol,
            annotations: n.annotations,
            beam: n.beam,
            lyric: n.lyric,
            source: n.source
        ))
    case .chord(let c):
        let dur = reduceFraction(
            numerator: c.duration.numerator * q,
            denominator: c.duration.denominator * p
        )
        return .chord(Chord(
            notes: c.notes,
            duration: dur,
            decorations: c.decorations,
            chordSymbol: c.chordSymbol,
            annotations: c.annotations,
            beam: c.beam,
            ties: c.ties,
            slurs: c.slurs,
            lyric: c.lyric,
            source: c.source
        ))
    default:
        return event
    }
}

private func reduceFraction(numerator: Int, denominator: Int) -> Fraction {
    guard numerator != 0 else { return Fraction(numerator: 0, denominator: 1) }
    let g = gcdPrivate(abs(numerator), abs(denominator))
    return Fraction(numerator: numerator / g, denominator: denominator / g)
}

private func gcdPrivate(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcdPrivate(b, a % b) }
