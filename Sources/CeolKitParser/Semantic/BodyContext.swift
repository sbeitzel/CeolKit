import Foundation
import CeolKitModel

// MARK: - VoiceAccumulator

struct VoiceAccumulator {
    var closedMeasures: [Measure] = []
    var staveBreakIndices: [Int] = []
    var currentEvents: [Event] = []
    var lastBarLine: BarLine? = nil
    var measureSource: SourceRange
    var unitNoteLength: Fraction
    // Set by BodyContext after a barline when [M:...] changed the meter mid-measure;
    // consumed by the next closeWith to tag that measure's meter change for renderers.
    var pendingMeter: Meter? = nil

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
        let src = measureSourceSpan(
            events: currentEvents,
            openingBar: lastBarLine,
            closingBar: barLine,
            fallback: measureSource
        )
        let meterTag = pendingMeter
        pendingMeter = nil
        let measure = Measure(
            openingBar: lastBarLine,
            events: currentEvents,
            closingBar: barLine,
            endingNumber: endingNumber,
            source: src,
            meter: meterTag
        )
        closedMeasures.append(measure)
        currentEvents = []
        lastBarLine = barLine
    }
}

// MARK: - BodyContext

/// Mutable state threaded through music body processing.
struct BodyContext {
    var unitNoteLength: Fraction
    var meter: Meter
    var key: KeySignature
    var userSymbols: [Character: Decoration]
    var macros: [MacroDefinition]

    /// Bar-scoped accidental memory, one table per voice.
    ///
    /// ABC §4.2 scopes a written accidental to the rest of the bar *in the voice that wrote
    /// it*: a `^F` in the melody must not make the harmony's `F` sound or print as F♯.  A
    /// voice's table is created on first use, so a voice that never writes an accidental
    /// costs nothing.
    private var accidentalScopes: [String: AccidentalScope] = [:]
    /// Baseline alterations a newly created scope starts from.  Tune-wide today; issue #66
    /// makes the key per voice, at which point this is looked up from the voice instead.
    private var scopeKeyAlterations: [DiatonicStep: Alteration]

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

    // I:linebreak settings — ABC 2.2 §9.2 — default is I:linebreak <EOL> $
    var linebreakChars: Set<Character> = ["$"] // $ and/or !
    var linebreakOnEOL: Bool = true            // <EOL>

    // Signals that [M:…] fired since the last barline; used to tag the next measure.
    var meterChangedSinceLastBar: Bool = false

    init(
        unitNoteLength: Fraction,
        meter: Meter,
        key: KeySignature,
        userSymbols: [Character: Decoration],
        macros: [MacroDefinition],
        headerVoices: [String: VoiceProperties] = [:],
        linebreakChars: Set<Character> = ["$"],
        linebreakOnEOL: Bool = true
    ) {
        self.unitNoteLength = unitNoteLength
        self.meter = meter
        self.key = key
        self.userSymbols = userSymbols
        self.macros = macros
        self.scopeKeyAlterations = keyAlterations(for: key)
        self.voiceProperties = headerVoices
        self.linebreakChars = linebreakChars
        self.linebreakOnEOL = linebreakOnEOL
    }

    mutating func splitCurrentStave() {
        voiceData[currentVoiceId]?.markStaveBoundary()
    }

    // MARK: Accidental scope (per voice)

    /// The effective alteration for a pitch in the *current* voice: that voice's bar memory
    /// first, then the key signature.  A voice with no table yet has empty bar memory, so an
    /// unrecorded voice resolves straight to the key — no need to materialise the table here.
    func resolveAccidental(step: DiatonicStep, octave: Int) -> Alteration {
        accidentalScopes[currentVoiceId]?.resolve(step: step, octave: octave)
            ?? scopeKeyAlterations[step]
            ?? .natural
    }

    /// Records a written accidental into the current voice's bar memory.
    mutating func recordAccidental(step: DiatonicStep, octave: Int, alteration: Alteration) {
        accidentalScopes[
            currentVoiceId,
            default: AccidentalScope(keyAlterations: scopeKeyAlterations)
        ].record(step: step, octave: octave, alteration: alteration)
    }

    /// Clears the current voice's bar memory at a bar line.  Other voices keep theirs: they
    /// reach their own bar lines on their own lines, and in a shared bar the two voices do
    /// not necessarily cross the bar at the same point in the source.
    mutating func resetBarAccidentals() {
        accidentalScopes[currentVoiceId]?.resetBar()
    }

    /// Re-seeds every voice's scope after a key change, dropping all bar memory — what the
    /// single shared scope did before, generalised to N voices.  `[K:]` is tune-wide today;
    /// issue #66 makes it voice-local.
    mutating func rekeyAccidentalScopes(_ key: KeySignature) {
        scopeKeyAlterations = keyAlterations(for: key)
        accidentalScopes.removeAll()
    }

    // Returns voices in the order they were first encountered.
    func voices(orderedBy order: [String]) -> [(String, VoiceAccumulator)] {
        order.compactMap { id in voiceData[id].map { (id, $0) } }
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
            source: eventSourceRange(event) ?? .emptySourceRange,
            unitNoteLength: unitNoteLength
        )].currentEvents.append(event)
    }

    mutating func emitSpaceBreak(source: SourceRange) {
        emit(.spacer(Spacer(width: 0, source: source)))
    }

    mutating func closeCurrentMeasure(barLine: BarLine) {
        voiceData[currentVoiceId, default: VoiceAccumulator(
            source: barLine.source,
            unitNoteLength: unitNoteLength
        )].closeWith(barLine: barLine, endingNumber: pendingEndingNumber)
        pendingEndingNumber = nil
        if meterChangedSinceLastBar {
            voiceData[currentVoiceId]?.pendingMeter = meter
            meterChangedSinceLastBar = false
        }
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
                staffProperties: properties.staffProperties.staffLines != 5
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
        let src = source ?? graceSource ?? .emptySourceRange
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
                source: acc.closedMeasures[i].source,
                meter: acc.closedMeasures[i].meter
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

    /// Retroactively increments the `slurs.closes` count on the last note in
    /// `currentEvents` (skipping spacers).  Returns true if a note was found and updated.
    mutating func addSlurCloseToLastNote() -> Bool {
        guard var acc = voiceData[currentVoiceId] else { return false }
        for i in stride(from: acc.currentEvents.count - 1, through: 0, by: -1) {
            switch acc.currentEvents[i] {
            case .spacer:
                continue
            case .note(let n):
                let updated = SlurState(opens: n.slurs.opens, closes: n.slurs.closes + 1)
                acc.currentEvents[i] = .note(Note(
                    pitch: n.pitch,
                    writtenAccidental: n.writtenAccidental,
                    displayedAccidental: n.displayedAccidental,
                    duration: n.duration,
                    ties: n.ties,
                    slurs: updated,
                    decorations: n.decorations,
                    chordSymbol: n.chordSymbol,
                    annotations: n.annotations,
                    beam: n.beam,
                    lyric: n.lyric,
                    source: n.source
                ))
                voiceData[currentVoiceId] = acc
                return true
            case .chord(let c):
                let updated = SlurState(opens: c.slurs.opens, closes: c.slurs.closes + 1)
                acc.currentEvents[i] = .chord(Chord(
                    notes: c.notes,
                    duration: c.duration,
                    decorations: c.decorations,
                    chordSymbol: c.chordSymbol,
                    annotations: c.annotations,
                    beam: c.beam,
                    ties: c.ties,
                    slurs: updated,
                    lyric: c.lyric,
                    source: c.source
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

struct TupletState {
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
