import Foundation
import CeolKitModel

// MARK: - VoiceAccumulator

struct VoiceAccumulator {
    var closedMeasures: [Measure] = []
    var staveBreakIndices: [Int] = []
    var currentEvents: [Event] = []
    var lastBarLine: BarLine? = nil
    var measureSource: SourceRange
    /// The unit note length the voice's *first* measure is written against — what
    /// `Voice.unitNoteLength` reports and what the beam resolver starts from.  Moves only
    /// while the voice has no music; an `L:` after that is a change, not an opening.
    var openingUnitNoteLength: Fraction
    /// The unit note length in force now.  Seeds an `&` layer opened from here, and is what
    /// a further `L:` is measured against.
    var unitNoteLength: Fraction
    /// The unit note length the measures being closed are counted in — what every closed
    /// measure is stamped with.
    ///
    /// This lags `unitNoteLength` by exactly the deferral `pendingUnitNoteLength` describes:
    /// an `L:` written against a bar line takes effect at the bar the next note falls in, and
    /// until that bar closes the measures still being written are in the old unit.
    var effectiveUnitNoteLength: Fraction
    // Set by VoiceState after a barline when the tune's meter has moved on since this voice
    // last reported it; consumed by the next closeWith to tag that measure for renderers.
    var pendingMeter: Meter? = nil
    /// An `L:` that moved the unit note length part way through the voice, paired with the
    /// number of musical events the measure then being written already held.
    ///
    /// Consumed by the close of the measure the first note after the change falls in — this
    /// one where music follows in the bar, the next where the field was written against the
    /// bar line, which is where ABC habitually puts a mid-tune field (#85).
    var pendingUnitNoteLength: (length: Fraction, after: Int)? = nil

    init(source: SourceRange, unitNoteLength: Fraction) {
        self.measureSource = source
        self.openingUnitNoteLength = unitNoteLength
        self.unitNoteLength = unitNoteLength
        self.effectiveUnitNoteLength = unitNoteLength
    }

    /// How many staves of this voice are finished — the index of the stave now being
    /// written.  Boundaries that close no measures are dropped when the staves are sliced
    /// (a lone `V:` line before any music makes one), so they are not counted here either.
    var completedStaveCount = 0

    /// True once any musical content has landed in this voice — a closed measure, or a
    /// non-spacer event in the measure now being written.
    ///
    /// What it distinguishes is a field stated at the head of a voice from one stated part
    /// way through it: the first says what the voice opens in, the second is a change.
    var hasMusic: Bool {
        !closedMeasures.isEmpty || currentEvents.contains {
            if case .spacer = $0 { return false }
            return true
        }
    }

    /// True when measures or events have accumulated since the last boundary, so the stave
    /// now being written already holds music.
    var hasStaveInProgress: Bool {
        if closedMeasures.count > staveBreakIndices.last ?? 0 { return true }
        return currentEvents.contains {
            if case .spacer = $0 { return false }
            return true
        }
    }

    /// True when the measure now being written holds music, so the last bar line the voice
    /// crossed is behind it rather than immediately before it.  What an `&` needs in order to
    /// know whether winding back one bar line means "the start of this bar" or "the start of
    /// the one before it" (§7.4).
    var hasOpenMeasure: Bool {
        currentEvents.contains {
            if case .spacer = $0 { return false }
            return true
        }
    }

    /// How much music the measure now being written holds.  Spacers are not music: they
    /// separate beam groups, and one sits either side of an inline field.
    var musicalEventCount: Int {
        currentEvents.reduce(into: 0) { count, event in
            if case .spacer = event { return }
            count += 1
        }
    }

    /// Records an `L:` met here, to be carried by whichever measure the next note lands in.
    mutating func markUnitNoteLengthChange(_ length: Fraction) {
        pendingUnitNoteLength = (length, musicalEventCount)
    }

    /// Appends a bar with no music in it, to keep an `&` overlay's measures aligned with the
    /// stave's own.  It draws nothing: the voice underneath owns the staff's furniture.
    mutating func appendEmptyMeasure(source: SourceRange) {
        closedMeasures.append(Measure(
            openingBar: lastBarLine,
            events: [],
            closingBar: BarLine(kind: .single, source: source),
            endingNumber: nil,
            source: source,
            meter: nil,
            unitNoteLength: effectiveUnitNoteLength
        ))
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
            // Nothing was written, so nothing can have followed the change: it still belongs
            // to the measure the next note falls in, counted from that measure's start.
            pendingUnitNoteLength?.after = 0
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
        if let change = pendingUnitNoteLength {
            if musicalEventCount > change.after {
                effectiveUnitNoteLength = change.length
                pendingUnitNoteLength = nil
            } else {
                pendingUnitNoteLength = (change.length, 0)
            }
        }
        let measure = Measure(
            openingBar: lastBarLine,
            events: currentEvents,
            closingBar: barLine,
            endingNumber: endingNumber,
            source: src,
            meter: meterTag,
            unitNoteLength: effectiveUnitNoteLength
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

    /// The `K:` this voice stated before any of its music, or `nil` while the tune's stands —
    /// ABC §7.3, which asks for a field that sets a music property to be repeated in every
    /// voice it applies to, and so reads a `K:` as belonging to the voice that carries it.
    ///
    /// Only what the voice *opens* in, which is what gets drawn at the head of its staff.  A
    /// later `K:` moves `accidentals` and leaves this alone: a key change part way through a
    /// staff is not drawn at all yet, and reporting it here would put the wrong signature at
    /// the head of the whole voice rather than no signature at the point of change.
    var openingKey: KeySignature?

    /// The `L:` this voice stated before any of its music, or `nil` while the tune's stands.
    /// Mirrored into `accumulator.openingUnitNoteLength`, which the first measure's beams are
    /// grouped against.  A later `L:` is a change rather than an opening: it lands on the
    /// measure it falls in and leaves this alone, exactly as a later `K:` leaves `openingKey`.
    var openingUnitNoteLength: Fraction?

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
    /// Which verse the next `w:` line for this voice writes: the `w:` lines following one
    /// music line are its verses, in source order, and `recordLyricAnchors` resets this
    /// wherever a new music line resets the anchor they align against.
    var lyricVerse: Int = 0

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

    /// Moves this voice's unit note length.
    ///
    /// Before any music it is what the voice opens in; after, it is a change, and it takes
    /// effect at the measure being written when the `L:` was met.  A change part way through
    /// a bar starts one note or two early — `Event.duration` is counted in unit note lengths
    /// and a measure carries one divisor, so there is nowhere finer for it to land — which is
    /// the case ABC itself gives no meaning to, since the durations either side of it would
    /// then be written in different units with nothing marking the seam.
    mutating func setUnitNoteLength(_ length: Fraction) {
        accumulator.unitNoteLength = length
        if accumulator.hasMusic {
            accumulator.markUnitNoteLengthChange(length)
        } else {
            openingUnitNoteLength = length
            accumulator.openingUnitNoteLength = length
            accumulator.effectiveUnitNoteLength = length
        }
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
        defer { lyricVerse += 1 }
        // Collect all events from closedMeasures[anchor...] + currentEvents
        var allEvents: [Event] = []
        for i in lyricAnchor..<accumulator.closedMeasures.count {
            allEvents += accumulator.closedMeasures[i].events
        }
        allEvents += accumulator.currentEvents

        let aligned = LyricAligner.align(tokens: tokens, to: allEvents, verse: lyricVerse)

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
                meter: m.meter,
                unitNoteLength: m.unitNoteLength
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
                    lyrics: n.lyrics,
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
                    lyrics: n.lyrics,
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
                    lyrics: c.lyrics,
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

// MARK: - VoiceKey

/// Which accumulating voice a piece of music belongs to.
///
/// Usually a voice a `V:` field named.  An `&` (§7.4) opens a *temporary* voice alongside it,
/// and that one has no `V:`, no properties and no place in the print order — it is drawn as a
/// second tenant of its base voice's staff.  Both kinds accumulate identically, so both are
/// keyed the same way and the walker threads one type.
struct VoiceKey: Hashable {
    /// The id a `V:` gave, which is what the model calls the voice.
    let base: String
    /// `0` for the voice itself; *n* for the music after its *n*th `&`.
    let overlay: Int

    init(_ base: String, overlay: Int = 0) {
        self.base = base
        self.overlay = overlay
    }

    var isOverlay: Bool { overlay > 0 }

    /// The voice this one overlays — itself, when it overlays nothing.
    var primary: VoiceKey { VoiceKey(base) }

    /// The layer an `&` written while standing in this one opens.
    ///
    /// The walker resets the cursor to the voice at the head of every line that does not
    /// itself open with `&`, so the first `&` of an ordinary line reopens layer 1 and its
    /// music joins what earlier lines put there — one `&` on each of two lines is one
    /// temporary voice, not two — while a line that *begins* with `&` keeps the cursor and
    /// so stacks a further layer over the same music.
    var nextOverlay: VoiceKey { VoiceKey(base, overlay: overlay + 1) }
}

// MARK: - BodyContext

/// Tune-wide state threaded through music body processing.
///
/// Deliberately has no notion of a "current" voice: every voice-scoped operation takes the
/// voice id from the caller, which threads it down the walk chain.  A method cannot reach a
/// voice it was not handed.
struct BodyContext {
    /// The tune's `L:` — the header's, or the default for its meter.  It is the value a voice
    /// is written against until that voice states an `L:` of its own; nothing moves it, because
    /// an `L:` in the body belongs to the voice that carries it (§7.3).
    let unitNoteLength: Fraction
    private(set) var meter: Meter
    /// The meter the tune opened in — every voice's first measure is in it, whatever `meter`
    /// has moved on to by the time the body has been walked.  What the beam resolver starts
    /// from, with `Measure.meter` moving it on from there.
    let openingMeter: Meter
    /// Bumped by every `[M:]`, so each voice can tag its own next measure exactly once.
    private(set) var meterGeneration: Int = 0
    /// The tune's `K:`, governing every voice that does not state one of its own.  Like
    /// `unitNoteLength`, fixed for the tune: a body `K:` moves one voice, not this.
    let key: KeySignature
    /// Always derived from `key`.
    let keySignatureAlterations: [DiatonicStep: Alteration]
    var userSymbols: [Character: Decoration]

    // Voice table — created on first musical content, never eagerly, so a voice that was
    // declared and never written to has no entry here.  `declaredVoices` is what keeps it
    // from being lost: a `V:` field is a declaration whether or not any note follows it.
    private(set) var voices: [VoiceKey: VoiceState] = [:]

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
    /// The `&` that opened each temporary voice (§7.4).  Its presence is also what says a
    /// layer exists at all: the states themselves live in `voices`, keyed by `VoiceKey`.
    private(set) var overlaySources: [VoiceKey: SourceRange] = [:]

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
        self.openingMeter = meter
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
        _ key: VoiceKey,
        source: @autoclosure () -> SourceRange,
        _ body: (inout VoiceState) -> R
    ) -> R {
        // Seeded from the tune, never from whichever voice was walked last: a voice that
        // states no `K:`/`L:` of its own is written against the tune's, not against its
        // neighbour's.
        let unitLen = unitNoteLength
        let alterations = keySignatureAlterations
        // Creating state for an id nothing has named yet also gives it a place in the print
        // order.  Belt and braces — the walker's cursor only ever holds an id that is already
        // in `voiceOrder` — but it makes "has music" imply "is printed" true by construction
        // rather than by inspection of every path that can move the cursor.
        if voices[key] == nil, !key.isOverlay, !voiceOrder.contains(key.base) {
            voiceOrder.append(key.base)
        }
        return body(&voices[key, default: VoiceState(
            accumulator: VoiceAccumulator(source: source(), unitNoteLength: unitLen),
            accidentals: AccidentalScope(keyAlterations: alterations)
        )])
    }

    /// The voice the walker starts in: the first the header declared, or the implicit `"1"`
    /// when it declared none.  Music written before the tune's first inline `[V:]` belongs to
    /// the first voice on the page, not to a voice the header never mentioned.
    var initialVoice: VoiceKey { VoiceKey(voiceOrder.first ?? "1") }

    /// Read-only access.  Never allocates, so a voice that writes nothing costs nothing.
    func voice(_ key: VoiceKey) -> VoiceState? { voices[key] }

    /// Every voice of the tune in print order, paired with its state.
    ///
    /// A `nil` state is a voice a `V:` field declared and no music ever reached — it is still
    /// a voice, and the caller emits it with empty staves.  The one id that can be dropped
    /// here is the implicit `"1"` of a tune whose header named its voices: a placeholder no
    /// one declared and nothing wrote to.
    func orderedVoices() -> [(String, VoiceState?)] {
        voiceOrder.compactMap { id in
            guard let state = voices[VoiceKey(id)] else {
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
    ///
    /// A meter change takes effect at a bar line, so for most voices "next" means the measure
    /// after the one they are in — which is what the generation counter gives them when they
    /// next cross one.  The voice the field was *written* in is the exception: it is standing
    /// at the point of change, so where its current measure has not begun yet — `| [M:3/4] …`,
    /// the field just past a bar line — the change is that measure's, not the one after it.
    mutating func setMeter(_ newMeter: Meter, in voice: VoiceKey) {
        meter = newMeter
        meterGeneration += 1
        // Only a voice that already exists: a `M:` before any music is the tune's own, and
        // materialising a voice for it would print a staff nothing was written to.
        guard var state = voices[voice], !state.accumulator.hasOpenMeasure else { return }
        state.accumulator.pendingMeter = newMeter
        state.lastTaggedMeterGeneration = meterGeneration
        voices[voice] = state
    }

    // MARK: Key and unit note length

    /// Moves the key for one voice.  Re-seeds that voice's accidental scope and drops its bar
    /// memory; every other voice keeps both, because a `K:` in the body belongs to the voice
    /// that carries it — §7.3 asks for such a field to be repeated in every voice it should
    /// affect, which is only meaningful if one voice's does not reach the rest.
    mutating func setKey(_ newKey: KeySignature, in voice: VoiceKey, source: SourceRange) {
        let alterations = keyAlterations(for: newKey)
        withVoice(voice, source: source) {
            if !$0.accumulator.hasMusic { $0.openingKey = newKey }
            $0.accidentals = AccidentalScope(keyAlterations: alterations)
        }
    }

    /// Moves the unit note length for one voice, likewise — at its head as the length the
    /// voice opens in, and part way through as a change carried on the measure it falls in.
    mutating func setUnitNoteLength(_ length: Fraction, in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.setUnitNoteLength(length) }
    }

    // MARK: Accidentals

    /// The effective alteration for a pitch in `voice`: that voice's bar memory first, then the
    /// key signature.  A voice with no state yet has no bar memory, so it resolves straight to
    /// the key — no need to materialise anything here.
    func resolveAccidental(step: DiatonicStep, octave: Int, in voice: VoiceKey) -> Alteration {
        voices[voice]?.accidentals.resolve(step: step, octave: octave)
            ?? keySignatureAlterations[step]
            ?? .natural
    }

    mutating func recordAccidental(
        step: DiatonicStep, octave: Int, alteration: Alteration,
        in voice: VoiceKey, source: SourceRange
    ) {
        withVoice(voice, source: source) {
            $0.accidentals.record(step: step, octave: octave, alteration: alteration)
        }
    }

    // MARK: Lyric anchors

    /// Marks, for every voice that exists, where the music line about to be walked begins.
    mutating func recordLyricAnchors() {
        for key in Array(voices.keys) {
            let anchor = voices[key]?.accumulator.closedMeasures.count ?? 0
            voices[key]?.lyricAnchor = anchor
            voices[key]?.lyricVerse = 0
        }
    }

    // MARK: Voice-scoped forwarding
    //
    // Each of these is the same operation on one `VoiceState`, with the voice named by the
    // caller.  They exist so the walker reads as `ctx.emit(event, in: voice)` rather than
    // spelling out a closure at every site.

    mutating func emit(_ event: Event, in voice: VoiceKey) {
        withVoice(voice, source: eventSourceRange(event) ?? .emptySourceRange) { $0.emit(event) }
    }

    mutating func emitSpaceBreak(source: SourceRange, in voice: VoiceKey) {
        withVoice(voice, source: source) { $0.emitSpaceBreak(source: source) }
    }

    mutating func closeMeasure(barLine: BarLine, in voice: VoiceKey) {
        let currentMeter = meter
        let generation = meterGeneration
        withVoice(voice, source: barLine.source) {
            $0.closeMeasure(barLine: barLine, currentMeter: currentMeter, generation: generation)
        }
    }

    mutating func splitStave(in voice: VoiceKey) {
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

    func isInGrace(_ voice: VoiceKey) -> Bool { voices[voice]?.isInGrace ?? false }

    mutating func startGrace(acciaccatura: Bool, source: SourceRange, in voice: VoiceKey) {
        withVoice(voice, source: source) { $0.startGrace(acciaccatura: acciaccatura, source: source) }
    }

    mutating func flushGrace(source: SourceRange? = nil, in voice: VoiceKey) {
        voices[voice]?.flushGrace(source: source)
    }

    mutating func appendGraceNote(_ note: Note, in voice: VoiceKey) {
        voices[voice]?.appendGraceNote(note)
    }

    mutating func startTuplet(p: Int, q: Int, r: Int, source: SourceRange, in voice: VoiceKey) {
        withVoice(voice, source: source) { $0.startTuplet(p: p, q: q, r: r, source: source) }
    }

    func isInTuplet(_ voice: VoiceKey) -> Bool { voices[voice]?.tuplet != nil }

    mutating func applyLyrics(_ tokens: [LyricToken], in voice: VoiceKey) {
        // No state means no music line to align against — nothing to do.
        voices[voice]?.applyLyrics(tokens)
    }

    mutating func applyDecorationToLastNote(_ decoration: Decoration, in voice: VoiceKey) -> Bool {
        guard voices[voice] != nil else { return false }
        return voices[voice]!.applyDecorationToLastNote(decoration)
    }

    mutating func addSlurCloseToLastNote(in voice: VoiceKey) -> Bool {
        guard voices[voice] != nil else { return false }
        return voices[voice]!.addSlurCloseToLastNote()
    }

    mutating func addPendingDecoration(_ decoration: Decoration, in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingDecorations.append(decoration) }
    }

    mutating func addPendingAnnotation(_ annotation: Annotation, in voice: VoiceKey) {
        withVoice(voice, source: annotation.source) { $0.pendingAnnotations.append(annotation) }
    }

    mutating func setPendingChordSymbol(_ symbol: ChordSymbol?, in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingChordSymbol = symbol }
    }

    mutating func setPendingEndingNumber(_ nums: [Int], in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.pendingEndingNumber = nums }
    }

    mutating func openSlur(in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.openSlurs += 1 }
    }

    mutating func carrySlurClose(in voice: VoiceKey, source: SourceRange) {
        withVoice(voice, source: source) { $0.closeSlurs += 1 }
    }

    mutating func consumeSlurs(in voice: VoiceKey, source: SourceRange) -> (opens: Int, closes: Int) {
        withVoice(voice, source: source) { $0.consumeSlurs() }
    }

    mutating func flushDecorations(in voice: VoiceKey, source: SourceRange) -> [Decoration] {
        withVoice(voice, source: source) { $0.flushDecorations() }
    }

    mutating func flushAnnotations(in voice: VoiceKey, source: SourceRange) -> [Annotation] {
        withVoice(voice, source: source) { $0.flushAnnotations() }
    }

    mutating func flushChordSymbol(in voice: VoiceKey, source: SourceRange) -> ChordSymbol? {
        withVoice(voice, source: source) { $0.flushChordSymbol() }
    }

    func lastElementWasSpace(in voice: VoiceKey) -> Bool {
        voices[voice]?.lastElementWasSpace ?? false
    }

    mutating func setLastElementWasSpace(_ value: Bool, in voice: VoiceKey) {
        // Only meaningful once the voice exists; a voice with no state has nothing to decorate.
        voices[voice]?.lastElementWasSpace = value
    }

    // MARK: Voice overlay (§7.4)

    /// Closes the bar `cursor` is writing, and with it the same bar of every `&` layer of the
    /// same voice that is standing in it.
    ///
    /// A bar line belongs to the staff, not to the layer that happened to be current when it
    /// was written: `c d e f & A A A A |` ends that bar for the voice and for its overlay
    /// alike, and closing only one of them would leave the other's bar hanging open until the
    /// end of the tune.  What decides is the bar each layer is *in*: an overlay written under
    /// an earlier line — the standard's own `&&` example — has wound the clock back behind
    /// the voice, and its bar lines are its own.
    mutating func closeBar(barLine: BarLine, in cursor: VoiceKey) {
        let bar = voices[cursor]?.accumulator.closedMeasures.count ?? 0
        // The cursor first, and by name rather than by lookup: a bar line can be the very
        // first thing in a voice, and that voice has no state to find yet.
        let together = [cursor] + voices.keys.filter {
            $0 != cursor && $0.base == cursor.base
                && voices[$0]?.accumulator.closedMeasures.count == bar
        }
        for key in together {
            closeMeasure(barLine: barLine, in: key)
            voices[key]?.accidentals.resetBar()
        }
    }

    /// Opens the temporary voice an `&` starts, with its first bar at `startMeasure` of the
    /// voice underneath.
    ///
    /// A layer that already exists — because an earlier line wound back into it — is brought
    /// forward to `startMeasure` rather than created again: two `&`s on two lines are the
    /// same temporary voice, and drawing them as two would put a third part on the staff that
    /// nobody wrote.  Where it has already written past `startMeasure` it stays where it is;
    /// the overrun is caught once, when the staves are built.
    mutating func openOverlay(_ key: VoiceKey, startingAt startMeasure: Int, source: SourceRange) {
        precondition(key.isOverlay, "openOverlay is for `&` layers, not for a voice itself")
        // The voice underneath exists from here on even if it never gets a note of its own:
        // the overlay is *its* music, and a voice with no state is a voice the model drops.
        withVoice(key.primary, source: source) { _ in }
        // A temporary voice is written in the same key and against the same unit as the
        // voice it overlays: it is that voice's own music, sounding at the same time.
        let unitLen = voices[key.primary]?.accumulator.unitNoteLength ?? unitNoteLength
        let alterations = voices[key.primary]?.accidentals.keyAlterations ?? keySignatureAlterations
        if voices[key] == nil {
            overlaySources[key] = source
            voices[key] = VoiceState(
                accumulator: VoiceAccumulator(source: source, unitNoteLength: unitLen),
                accidentals: AccidentalScope(keyAlterations: alterations)
            )
        }
        while voices[key]!.accumulator.closedMeasures.count < startMeasure {
            voices[key]!.accumulator.appendEmptyMeasure(source: source)
        }
        // §4.2 scopes an accidental to the bar in the voice that wrote it, and winding the
        // clock back starts a new bar in a new voice.
        voices[key]!.accidentals.resetBar()
    }

    /// Every `&` layer of one voice, outermost first, each with the `&` that opened it.
    func overlays(of base: String) -> [(source: SourceRange, state: VoiceState)] {
        overlaySources.keys
            .filter { $0.base == base }
            .sorted { $0.overlay < $1.overlay }
            .compactMap { key in voices[key].map { (overlaySources[key]!, $0) } }
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
            lyrics: n.lyrics,
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
            lyrics: c.lyrics,
            source: c.source
        ))
    default:
        return event
    }
}
