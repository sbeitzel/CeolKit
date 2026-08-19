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
    // Set by VoiceState after a barline when the tune's meter has moved on since this voice
    // last reported it; consumed by the next closeWith to tag that measure for renderers.
    var pendingMeter: Meter? = nil

    init(source: SourceRange, unitNoteLength: Fraction) {
        self.measureSource = source
        self.unitNoteLength = unitNoteLength
    }

    /// How many staves of this voice are finished — the index of the stave now being
    /// written.  Boundaries that close no measures are dropped when the staves are sliced
    /// (a lone `V:` line before any music makes one), so they are not counted here either.
    var completedStaveCount = 0

    /// True when measures or events have accumulated since the last boundary, so the stave
    /// now being written already holds music.
    var hasStaveInProgress: Bool {
        if closedMeasures.count > staveBreakIndices.last ?? 0 { return true }
        return currentEvents.contains {
            if case .spacer = $0 { return false }
            return true
        }
    }

    mutating func markStaveBoundary() {
        let idx = closedMeasures.count
        guard idx != staveBreakIndices.last else { return }  // no new measures since last split
        if idx > staveBreakIndices.last ?? 0 { completedStaveCount += 1 }
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

// MARK: - GraceState

/// An open `{…}` grace group.  Carries its own source so an unterminated group still has a
/// position to report when the line ends.
struct GraceState {
    let kind: GraceKind
    let source: SourceRange
    var notes: [Note] = []
}

// MARK: - TupletState

struct TupletState {
    let p: Int
    let q: Int
    let r: Int
    let source: SourceRange
    var events: [Event] = []
}

// MARK: - VoiceState

/// Everything scoped to a single voice.
///
/// A field added here is per-voice by construction; a field added to `BodyContext` is
/// tune-wide by construction.  That line is the whole point of the split — issue #60 was a
/// field that had ended up on the wrong side of it, and six more were sitting beside it.
///
/// Nothing in here can reach another voice: these methods see one `VoiceState` and no way
/// back to the table that holds it.
struct VoiceState {
    var accumulator: VoiceAccumulator

    /// Bar-scoped accidental memory — ABC §4.2 scopes a written accidental to the rest of the
    /// bar *in the voice that wrote it*, so a `^F` in the melody must not make the harmony's
    /// `F` sound or print as F♯.
    var accidentals: AccidentalScope

    // Pending attachments for this voice's next note/chord
    var pendingDecorations: [Decoration] = []
    var pendingAnnotations: [Annotation] = []
    var pendingChordSymbol: ChordSymbol? = nil
    var pendingEndingNumber: [Int]? = nil

    // Slur state
    var openSlurs: Int = 0
    var closeSlurs: Int = 0

    var grace: GraceState? = nil
    var tuplet: TupletState? = nil

    /// closedMeasures count before the current music line, so a following `w:` knows which
    /// measures belong to the line it annotates.
    var lyricAnchor: Int = 0

    /// Space tracking for post-note decoration.
    var lastElementWasSpace: Bool = false

    /// Which `[M:]` this voice last reported, as a generation counter rather than a value: a
    /// restated `[M:4/4]` in a 4/4 tune is still an event a renderer wants tagged, and `Meter`
    /// is not Equatable in any case.  A meter change is tune-wide — one conductor — but each
    /// voice crosses its own bar lines at its own point in the source, so the tag lands when
    /// this voice next closes a measure, not when the `[M:]` is parsed.
    ///
    /// Starts at 0 — the meter the tune opened in — even for a voice whose state is created
    /// after an `[M:]` has been parsed.  Voices are *written* one after another and *sound*
    /// together, so a voice's creation order says nothing about where its music sits in time:
    /// voice 2's first bar is still the tune's first bar.
    var lastTaggedMeterGeneration: Int = 0

    var isInGrace: Bool { grace != nil }

    // MARK: Event emission

    mutating func emit(_ event: Event) {
        if grace != nil {
            // Grace notes are accumulated; the note itself was already added to grace.notes
            return
        }
        if tuplet != nil {
            tuplet!.events.append(event)
            if tuplet!.events.count >= tuplet!.r {
                flushTuplet()
            }
            return
        }
        accumulator.currentEvents.append(event)
    }

    mutating func emitSpaceBreak(source: SourceRange) {
        emit(.spacer(Spacer(width: 0, source: source)))
    }

    mutating func closeMeasure(barLine: BarLine, currentMeter: Meter, generation: Int) {
        accumulator.closeWith(barLine: barLine, endingNumber: pendingEndingNumber)
        pendingEndingNumber = nil
        // Tag the measure *after* this bar line, matching where a tune-wide [M:] takes effect.
        if generation != lastTaggedMeterGeneration {
            accumulator.pendingMeter = currentMeter
            lastTaggedMeterGeneration = generation
        }
    }

    // MARK: Grace groups

    mutating func startGrace(acciaccatura: Bool, source: SourceRange) {
        grace = GraceState(kind: acciaccatura ? .acciaccatura : .appoggiatura, source: source)
    }

    mutating func flushGrace(source: SourceRange? = nil) {
        guard let open = grace else { return }
        let group = GraceGroup(kind: open.kind, notes: open.notes, source: source ?? open.source)
        grace = nil
        accumulator.currentEvents.append(.grace(group))
    }

    mutating func appendGraceNote(_ note: Note) {
        grace?.notes.append(note)
    }

    // MARK: Tuplets

    mutating func startTuplet(p: Int, q: Int, r: Int, source: SourceRange) {
        tuplet = TupletState(p: p, q: q, r: r, source: source)
    }

    mutating func flushTuplet() {
        guard let open = tuplet else { return }
        let adjustedEvents = open.events.map { applyTupletFactor(q: open.q, p: open.p, to: $0) }
        let t = Tuplet(p: open.p, q: open.q, r: open.r, events: adjustedEvents, source: open.source)
        tuplet = nil
        accumulator.currentEvents.append(.tuplet(t))
    }

    // MARK: Lyrics

    /// Applies lyrics to events from the music line just before this lyric field.
    /// Uses lyricAnchor to find which closed measures belong to the preceding line.
    mutating func applyLyrics(_ tokens: [LyricToken]) {
        // Collect all events from closedMeasures[anchor...] + currentEvents
        var allEvents: [Event] = []
        for i in lyricAnchor..<accumulator.closedMeasures.count {
            allEvents += accumulator.closedMeasures[i].events
        }
        allEvents += accumulator.currentEvents

        let aligned = LyricAligner.align(tokens: tokens, to: allEvents)

        // Write back: first update closedMeasures[anchor...], then currentEvents
        var offset = 0
        for i in lyricAnchor..<accumulator.closedMeasures.count {
            let m = accumulator.closedMeasures[i]
            let count = m.events.count
            let newEvents = Array(aligned[offset..<(offset + count)])
            accumulator.closedMeasures[i] = Measure(
                openingBar: m.openingBar,
                events: newEvents,
                closingBar: m.closingBar,
                endingNumber: m.endingNumber,
                source: m.source,
                meter: m.meter
            )
            offset += count
        }
        accumulator.currentEvents = Array(aligned[offset...])
    }

    // MARK: Retroactive edits to the last event

    /// Retroactively applies a decoration to the last note in currentEvents (skipping spacers).
    /// Returns true if successfully applied.
    mutating func applyDecorationToLastNote(_ decoration: Decoration) -> Bool {
        for i in stride(from: accumulator.currentEvents.count - 1, through: 0, by: -1) {
            switch accumulator.currentEvents[i] {
            case .spacer:
                continue
            case .note(let n):
                accumulator.currentEvents[i] = .note(Note(
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
        for i in stride(from: accumulator.currentEvents.count - 1, through: 0, by: -1) {
            switch accumulator.currentEvents[i] {
            case .spacer:
                continue
            case .note(let n):
                let updated = SlurState(opens: n.slurs.opens, closes: n.slurs.closes + 1)
                accumulator.currentEvents[i] = .note(Note(
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
                return true
            case .chord(let c):
                let updated = SlurState(opens: c.slurs.opens, closes: c.slurs.closes + 1)
                accumulator.currentEvents[i] = .chord(Chord(
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
                return true
            default:
                return false
            }
        }
        return false
    }

    // MARK: Pending-attachment drains

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

// MARK: - BodyContext

/// Tune-wide state threaded through music body processing.
///
/// Deliberately has no notion of a "current" voice: every voice-scoped operation takes the
/// voice id from the caller, which threads it down the walk chain.  A method cannot reach a
/// voice it was not handed.
struct BodyContext {
    var unitNoteLength: Fraction
    private(set) var meter: Meter
    /// Bumped by every `[M:]`, so each voice can tag its own next measure exactly once.
    private(set) var meterGeneration: Int = 0
    private(set) var key: KeySignature
    /// Always derived from `key`; `setKey` is the only thing that moves either.
    private(set) var keySignatureAlterations: [DiatonicStep: Alteration]
    var userSymbols: [Character: Decoration]

    // Voice table — created on first musical content, never eagerly, so a voice that was
    // declared and never written to has no entry here.  `declaredVoices` is what keeps it
    // from being lost: a `V:` field is a declaration whether or not any note follows it.
    private(set) var voices: [String: VoiceState] = [:]

    /// Every voice this tune knows about, in print order: the header's `V:` declarations
    /// first, then any the body introduced, in the order each was first seen.
    ///
    /// Seeded `["1"]` only when the header declared nothing — that entry is the implicit
    /// default voice, a placeholder rather than a declaration, which is why it is absent
    /// from `declaredVoices` and never printed unless music actually lands in it.
    private(set) var voiceOrder: [String]

    /// The ids an actual `V:` field named, header or inline.  These exist as voices even
    /// with no music: `%%score` may place a voice the body never switches into (issue #61).
    private(set) var declaredVoices: Set<String>
    var voiceProperties: [String: VoiceProperties] = [:]
    var voiceDirectives: [String: [CeolKitDirectiveScope]] = [:]
    var bodyTuneDirectives: [CeolKitDirectiveScope] = []
    /// `%%score` / `%%staves` met in the body, in source order, each already carrying the
    /// stave it governs from.
    var bodyStaffPlans: [StaffPlanChange] = []
    var hasExplicitVoice: Bool = false

    // I:linebreak settings — ABC 2.2 §9.2 — default is I:linebreak <EOL> $
    let linebreakChars: Set<Character>  // $ and/or !
    let linebreakOnEOL: Bool            // <EOL>

    init(
        unitNoteLength: Fraction,
        meter: Meter,
        key: KeySignature,
        userSymbols: [Character: Decoration],
        headerVoices: [String: VoiceProperties] = [:],
        headerVoiceOrder: [String] = [],
        linebreakChars: Set<Character> = ["$"],
        linebreakOnEOL: Bool = true
    ) {
        self.voiceOrder = headerVoiceOrder.isEmpty ? ["1"] : headerVoiceOrder
        self.declaredVoices = Set(headerVoiceOrder)
        self.unitNoteLength = unitNoteLength
        self.meter = meter
        self.key = key
        self.keySignatureAlterations = keyAlterations(for: key)
        self.userSymbols = userSymbols
        self.voiceProperties = headerVoices
        self.linebreakChars = linebreakChars
        self.linebreakOnEOL = linebreakOnEOL
    }

    // MARK: Voice access

    /// Mutating access to one voice, creating its state on first musical content.
    mutating func withVoice<R>(
        _ id: String,
        source: @autoclosure () -> SourceRange,
        _ body: (inout VoiceState) -> R
    ) -> R {
        let unitLen = unitNoteLength
        let alterations = keySignatureAlterations
        // Creating state for an id nothing has named yet also gives it a place in the print
        // order.  Belt and braces — the walker's cursor only ever holds an id that is already
        // in `voiceOrder` — but it makes "has music" imply "is printed" true by construction
        // rather than by inspection of every path that can move the cursor.
        if voices[id] == nil, !voiceOrder.contains(id) { voiceOrder.append(id) }
        return body(&voices[id, default: VoiceState(
            accumulator: VoiceAccumulator(source: source(), unitNoteLength: unitLen),
            accidentals: AccidentalScope(keyAlterations: alterations)
        )])
    }

    /// The voice the walker starts in: the first the header declared, or the implicit `"1"`
    /// when it declared none.  Music written before the tune's first inline `[V:]` belongs to
    /// the first voice on the page, not to a voice the header never mentioned.
    var initialVoice: String { voiceOrder.first ?? "1" }

    /// Read-only access.  Never allocates, so a voice that writes nothing costs nothing.
    func voice(_ id: String) -> VoiceState? { voices[id] }

    /// Every voice of the tune in print order, paired with its state.
    ///
    /// A `nil` state is a voice a `V:` field declared and no music ever reached — it is still
    /// a voice, and the caller emits it with empty staves.  The one id that can be dropped
    /// here is the implicit `"1"` of a tune whose header named its voices: a placeholder no
    /// one declared and nothing wrote to.
    func orderedVoices() -> [(String, VoiceState?)] {
        voiceOrder.compactMap { id in
            guard let state = voices[id] else {
                return declaredVoices.contains(id) ? (id, nil) : nil
            }
            return (id, state)
        }
    }

    /// Records a `V:` switch.  Does *not* move any cursor — the walker owns that, and assigns
    /// the returned id to the voice it is threading.
    mutating func registerVoice(id: String, properties: VoiceProperties) {
        if !voiceOrder.contains(id) { voiceOrder.append(id) }
        declaredVoices.insert(id)
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

    // MARK: Meter

    /// The only way to move the meter.  Every voice tags its own next measure exactly once.
    mutating func setMeter(_ newMeter: Meter) {
        meter = newMeter
        meterGeneration += 1
    }

    // MARK: Key

    /// The only way to move the key.  Re-seeds every voice's scope and drops all bar memory —
    /// what the single shared scope did before, generalised to N voices.  `[K:]` is tune-wide
    /// today; issue #66 makes it voice-local.
    mutating func setKey(_ newKey: KeySignature) {
        key = newKey
        keySignatureAlterations = keyAlterations(for: newKey)
        let alterations = keySignatureAlterations
        for id in voices.keys {
            voices[id]?.accidentals = AccidentalScope(keyAlterations: alterations)
        }
    }

    // MARK: Accidentals

    /// The effective alteration for a pitch in `voice`: that voice's bar memory first, then the
    /// key signature.  A voice with no state yet has no bar memory, so it resolves straight to
    /// the key — no need to materialise anything here.
    func resolveAccidental(step: DiatonicStep, octave: Int, in voice: String) -> Alteration {
        voices[voice]?.accidentals.resolve(step: step, octave: octave)
            ?? keySignatureAlterations[step]
            ?? .natural
    }

    mutating func recordAccidental(
        step: DiatonicStep, octave: Int, alteration: Alteration,
        in voice: String, source: SourceRange
    ) {
        withVoice(voice, source: source) {
            $0.accidentals.record(step: step, octave: octave, alteration: alteration)
        }
    }

    /// Clears one voice's bar memory at a bar line.  Other voices keep theirs: they reach their
    /// own bar lines on their own lines, and in a shared bar two voices do not necessarily
    /// cross the bar at the same point in the source.
    mutating func resetBarAccidentals(in voice: String) {
        voices[voice]?.accidentals.resetBar()
    }

    // MARK: Lyric anchors

    /// Marks, for every voice that exists, where the music line about to be walked begins.
    mutating func recordLyricAnchors() {
        for id in Array(voices.keys) {
            let anchor = voices[id]?.accumulator.closedMeasures.count ?? 0
            voices[id]?.lyricAnchor = anchor
        }
    }

    // MARK: Voice-scoped forwarding
    //
    // Each of these is the same operation on one `VoiceState`, with the voice named by the
    // caller.  They exist so the walker reads as `ctx.emit(event, in: voice)` rather than
    // spelling out a closure at every site.

    mutating func emit(_ event: Event, in voice: String) {
        withVoice(voice, source: eventSourceRange(event) ?? .emptySourceRange) { $0.emit(event) }
    }

    mutating func emitSpaceBreak(source: SourceRange, in voice: String) {
        withVoice(voice, source: source) { $0.emitSpaceBreak(source: source) }
    }

    mutating func closeMeasure(barLine: BarLine, in voice: String) {
        let currentMeter = meter
        let generation = meterGeneration
        withVoice(voice, source: barLine.source) {
            $0.closeMeasure(barLine: barLine, currentMeter: currentMeter, generation: generation)
        }
    }

    mutating func splitStave(in voice: String) {
        voices[voice]?.accumulator.markStaveBoundary()
    }

    /// The index of the stave now being written, for the tune as a whole.
    ///
    /// Every voice finishes a stave at the same system boundary, so the voices are expected
    /// to agree; taking the maximum reads correctly when they do and tolerates a voice the
    /// body has not written to yet, which has finished none.
    var currentStaveIndex: Int {
        voices.values.map(\.accumulator.completedStaveCount).max() ?? 0
    }

    /// True when some voice has already written into the stave now being written, so
    /// anything landing here lands part-way through a system.
    var hasStaveInProgress: Bool {
        voices.values.contains(where: \.accumulator.hasStaveInProgress)
    }

    func isInGrace(_ voice: String) -> Bool { voices[voice]?.isInGrace ?? false }

    mutating func startGrace(acciaccatura: Bool, source: SourceRange, in voice: String) {
        withVoice(voice, source: source) { $0.startGrace(acciaccatura: acciaccatura, source: source) }
    }

    mutating func flushGrace(source: SourceRange? = nil, in voice: String) {
        voices[voice]?.flushGrace(source: source)
    }

    mutating func appendGraceNote(_ note: Note, in voice: String) {
        voices[voice]?.appendGraceNote(note)
    }

    mutating func startTuplet(p: Int, q: Int, r: Int, source: SourceRange, in voice: String) {
        withVoice(voice, source: source) { $0.startTuplet(p: p, q: q, r: r, source: source) }
    }

    func isInTuplet(_ voice: String) -> Bool { voices[voice]?.tuplet != nil }

    mutating func applyLyrics(_ tokens: [LyricToken], in voice: String) {
        // No state means no music line to align against — nothing to do.
        voices[voice]?.applyLyrics(tokens)
    }

    mutating func applyDecorationToLastNote(_ decoration: Decoration, in voice: String) -> Bool {
        guard voices[voice] != nil else { return false }
        return voices[voice]!.applyDecorationToLastNote(decoration)
    }

    mutating func addSlurCloseToLastNote(in voice: String) -> Bool {
        guard voices[voice] != nil else { return false }
        return voices[voice]!.addSlurCloseToLastNote()
    }

    mutating func addPendingDecoration(_ decoration: Decoration, in voice: String, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingDecorations.append(decoration) }
    }

    mutating func addPendingAnnotation(_ annotation: Annotation, in voice: String) {
        withVoice(voice, source: annotation.source) { $0.pendingAnnotations.append(annotation) }
    }

    mutating func setPendingChordSymbol(_ symbol: ChordSymbol?, in voice: String, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingChordSymbol = symbol }
    }

    mutating func setPendingEndingNumber(_ nums: [Int], in voice: String, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingEndingNumber = nums }
    }

    mutating func openSlur(in voice: String, source: SourceRange) {
        withVoice(voice, source: source) { $0.openSlurs += 1 }
    }

    mutating func carrySlurClose(in voice: String, source: SourceRange) {
        withVoice(voice, source: source) { $0.closeSlurs += 1 }
    }

    mutating func consumeSlurs(in voice: String, source: SourceRange) -> (opens: Int, closes: Int) {
        withVoice(voice, source: source) { $0.consumeSlurs() }
    }

    mutating func flushDecorations(in voice: String, source: SourceRange) -> [Decoration] {
        withVoice(voice, source: source) { $0.flushDecorations() }
    }

    mutating func flushAnnotations(in voice: String, source: SourceRange) -> [Annotation] {
        withVoice(voice, source: source) { $0.flushAnnotations() }
    }

    mutating func flushChordSymbol(in voice: String, source: SourceRange) -> ChordSymbol? {
        withVoice(voice, source: source) { $0.flushChordSymbol() }
    }

    func lastElementWasSpace(in voice: String) -> Bool {
        voices[voice]?.lastElementWasSpace ?? false
    }

    mutating func setLastElementWasSpace(_ value: Bool, in voice: String) {
        // Only meaningful once the voice exists; a voice with no state has nothing to decorate.
        voices[voice]?.lastElementWasSpace = value
    }
}

// MARK: - Tuplet duration adjustment

private func applyTupletFactor(q: Int, p: Int, to event: Event) -> Event {
    switch event {
    case .note(let n):
        let dur = reducedFraction(
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
        let dur = reducedFraction(
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
