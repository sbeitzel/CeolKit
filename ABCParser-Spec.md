# CeolKit Parser & Domain Model — Specification (v0.1)

**Status:** Draft for review
**Scope:** Architectural overview + core domain model
**Target language:** Swift
**Source standards:** ABC notation standard v2.2 (Walshaw, draft) + CeolKit `EXTENSIONS.md`
**Audience:** CeolKit maintainers and contributors building or consuming the parser

---

## 1. Goals and non‑goals

### 1.1 Goals

1. Translate ABC source text into a **structured, typed, Swift-native representation** of musical intent.
2. **Separate two domains** that have historically been conflated in ABC tooling:
   - *Lexical / syntactic*: what the bytes of the file mean as ABC.
   - *Semantic / musical*: what notes, voices, parts, and decorations the tune contains, with state (key, meter, unit length) resolved.
3. Produce output that any number of back ends — staff‑notation renderer, MIDI exporter, MusicXML exporter, transposer, tune‑database indexer — can consume **without ever touching the original string**.
4. Preserve enough provenance (source ranges) that a renderer or editor can map every domain object back to the byte range it came from.
5. Be friendly to **strict + recoverable** diagnostics: a malformed input still yields a (partial) model plus a structured list of issues.
6. Treat CeolKit's three current `%%ceolkit:*` directives as **first‑class** members of the core model, alongside ABC v2.2 constructs.

### 1.2 Non‑goals (for this spec)

- Rendering / typesetting decisions (stem direction heuristics, page layout, font selection). The model carries the *intent* and any directive overrides; how to draw them is a different module's problem.
- Playback semantics beyond what ABC itself prescribes (e.g. swing interpretation, articulation timing curves).
- Round‑tripping perfectly to source text. A pretty‑printer is a separate, secondary tool.
- CeolKit's deprecated abcm2ps/abc2midi extensions (only the three currently documented in `EXTENSIONS.md` are in scope).

---

## 2. Pipeline overview

The parser is organised as a series of stages. Each stage has a well‑defined input and output type, can be inspected independently, and can be replaced for testing.

```
                +------------------+
  ABC source -->| 1. Source        |   String + line index
                +--------+---------+
                         |
                         v
                +------------------+
                | 2. Line classifier|  [LineKind] with raw payloads
                +--------+---------+
                         |
                         v
                +------------------+
                | 3. Tokenizer     |   Per-line tokens (music code)
                | (music-code only)|   Field-payload sub-parsers
                +--------+---------+
                         |
                         v
                +------------------+
                | 4. Syntactic AST |   ABCFile, ABCTune (raw)
                +--------+---------+
                         |
                         v
                +------------------+
                | 5. Semantic pass |   Resolve K:/L:/M:/V:/U:/m:
                |   (state mgr)    |   Apply file-header defaults
                +--------+---------+
                         |
                         v
                +------------------+
                | 6. Domain model  |   Score, Tune, Voice, Bar, ...
                +------------------+
```

Stages 1–4 are purely syntactic. Stage 5 resolves stateful information (current key signature, unit note length, active voice, redefinable symbol expansion, macro expansion) so that downstream consumers see *self-contained* musical events without having to re‑implement an interpreter. Stage 6 is the public, stable shape consumers depend on.

A consumer that wants to do a custom interpretation (e.g. a stylistic linter) may opt out of stage 5 and consume the AST directly. The AST is therefore part of the public surface, but with weaker stability guarantees than the domain model.

### 2.1 Why a separate "line classifier" stage

ABC's syntax is line‑oriented but with two complications:

- **Continuation** (`\` at end of music code line, `+:` for fields, `%` propagation) means a logical line is not always one physical line.
- **Inline fields** (`[K:G]`) embed full information‑field syntax inside music code.
- **Comments and stylesheet directives** can appear between continuations and must not break them.

Trying to handle all of this inside the music‑code tokenizer entangles concerns. A dedicated classifier walks the file once, emits a sequence of `LogicalLine` values (each tagged by kind, with a `SourceRange`), and exposes a recovery point at every blank line. The tokenizer then only has to understand one kind of line at a time.

### 2.2 Strict vs. loose interpretation

Per ABC v2.2 §12, files with `%abc-2.1` or higher in their version line are interpreted strictly; files without are interpreted leniently. The parser carries a `Dialect` value:

```swift
public enum Dialect {
    case strict(version: ABCVersion)   // e.g. .v2_2
    case loose                          // pre-2.1 or unversioned
}
```

Dialect affects:

- Whether outdated syntax (ABC §10) produces a warning, an auto‑rewrite, or a strict error.
- Decoration dialect (`I:decoration +` vs. `!…!`).
- Acceptance of legacy line continuations and chord syntax.

Dialect is determined from the version line / `I:abc-version` field early in stage 2 and is fixed for the remainder of the parse, except where individual tunes override it via their own `I:abc-version`.

---

## 3. Lexical layer

### 3.1 Encoding

- Default character set is UTF‑8. A BOM at offset 0 is stripped and ignored (§2.1 note).
- `I:abc-charset` in the file header switches the decoder before any text strings or lyrics are interpreted. Legal values are `iso-8859-1`..`iso-8859-10`, `us-ascii`, `utf-8`. The charset directive applies only to subsequent bytes; therefore the lexer reads in two passes when a non‑UTF‑8 charset is declared.
- Text strings additionally support the escapes documented in §8.2 (mnemonic `\'e`, TeX‑style `\"o`, named `\ss`, fallback `é`) — these are expanded in stage 4 as part of constructing `TextString` values, not in the lexer.

### 3.2 Tokens (music‑code lines only)

The tokenizer produces a flat `[Token]` per logical music‑code line. Tokens are *syntactic*: pitch alphabets, accidental marks, broken‑rhythm operators, etc. — they carry no music‑theoretic interpretation yet.

```swift
public enum Token {
    case noteLetter(Character, SourceRange)           // A..G, a..g
    case rest(RestKind, SourceRange)                  // z, x, Z, X, y
    case accidental(AccidentalToken, SourceRange)     // ^, ^^, =, _, __, ^k/n, _k/n
    case octaveMark(Int, SourceRange)                 // total ' minus , count
    case lengthMultiplier(Int, SourceRange)           // following digits
    case lengthDivisor(Int?, SourceRange)             // /, /2, //, /4
    case brokenRhythm(BrokenRhythm, SourceRange)      // >, <, >>, <<, >>>, <<<
    case barLine(BarToken, SourceRange)               // |, ||, |], [|, .|, :|, |:, ::, |1, |2, [1, [2
    case tieMark(SourceRange)                         // -
    case slurOpen(SourceRange)                        // (
    case slurClose(SourceRange)                       // )
    case graceOpen(GraceKind, SourceRange)            // { or {/
    case graceClose(SourceRange)                      // }
    case tupletMark(TupletSpec, SourceRange)          // (3, (p:q:r
    case chordOpen(SourceRange)                       // [
    case chordClose(SourceRange)                      // ]
    case decoration(DecorationToken, SourceRange)     // !pp!, !trill!, !D.C.alcoda!
    case shortDecoration(Character, SourceRange)      // . ~ H L M O P S T u v
    case chordSymbol(String, SourceRange)             // "Gm7"
    case annotation(AnnotationPosition, String, SourceRange) // "^above", "_below"
    case redefinableSymbol(Character, SourceRange)    // user-defined letter (resolved later)
    case spacer(Int, SourceRange)                     // y, y2 (whitespace-only in score)
    case codeContinuation(SourceRange)                // trailing backslash
    case overlayMark(SourceRange)                     // &
    case inlineFieldStart(Character, SourceRange)     // first char of [X:...]
    case inlineFieldBody(String, SourceRange)
    case inlineFieldEnd(SourceRange)
    case whitespace(SourceRange)                      // grouped, beam-relevant
    case unknown(Character, SourceRange)              // diagnostic recovery
}
```

`AccidentalToken` is the syntactic representation of an accidental mark as it appears in source. It is distinct from the semantic `Alteration` type (§6.3), which is normalised and carries a signed rational value. The conversion from `AccidentalToken` to `Alteration` happens in the semantic pass.

```swift
public enum AccidentalToken: Hashable {
    case sharp                                          // ^
    case doubleSharp                                    // ^^
    case flat                                           // _
    case doubleFlat                                     // __
    case natural                                        // =
    case rational(numerator: Int, denominator: Int, isSharp: Bool)  // ^k/n, _k/n
}
```

The `rational` case carries the numerator and denominator as written in the source (both positive `Int`s, unnormalised at this stage) and a flag for direction, since the `^`/`_` sigil is the only indicator of sign at the syntactic level. Normalisation and sign encoding happen when `Alteration` is constructed in the semantic pass.

`SourceRange` is `(file: URL?, byteOffset: Int, length: Int, line: Int, column: Int)`. Every parser output value carries a range so editors and diagnostics can point at the right byte.

### 3.3 Field‑payload sub‑lexers

Each information‑field type has its own micro‑parser invoked on its payload string. This keeps the main tokenizer simple: it knows fields exist, but doesn't know how to parse `Q: "Allegro" 1/4=120` or `K:D Phr ^f clef=bass`. The sub‑parsers live in `Parser/Fields/`, one per field kind, and produce typed AST nodes (see §5).

---

## 4. Line classification

After stripping line endings into a normalised line index, the classifier emits one `LogicalLine` per non‑empty, comment‑aware physical block:

```swift
public enum LogicalLine {
    case empty(SourceRange)
    case freeText(String, SourceRange)
    case commentOnly(String, SourceRange)
    case versionLine(String, SourceRange)              // leading %abc-2.2
    case stylesheetDirective(RawDirective, SourceRange) // %%foo bar
    case informationField(FieldId, RawPayload, SourceRange)  // X:1, K:G, etc.
    case fieldContinuation(RawPayload, SourceRange)    // +:...
    case musicCode(RawPayload, SourceRange)
}

public struct FieldId: Hashable {
    public let letter: Character     // X, T, K, m, w, W, V, s, r, I, …
}
```

Classification rules (per §2.2 and §3):

- A line matching `^[A-Za-z]:` is an information field. The single‑letter prefix plus `:` is *not* mistaken for music when `letter` is one of the field‑reserved letters (full table in §6.1).
- A line matching `^\+:` is a field continuation; it inherits its `FieldId` from the most recent prior `informationField` whose context permits continuation.
- A line beginning with `%%` is a stylesheet directive.
- A line whose first character is `%` (but not `%%`, not `%abc`) is a comment‑only line.
- A line with trailing `\` is concatenated with the next non‑directive, non‑comment line of the *same* kind (music code with music code, field with field via `+:`). Comments and directives between continuations are passed through unchanged in stage 5.

The classifier is **lossless**: every byte of the input is accounted for in some `LogicalLine.SourceRange`. This is what enables stage 6 to provide round‑trip source mapping.

---

## 5. Syntactic AST

The AST is the structure produced after stages 3 and 4 but before semantic resolution. It mirrors ABC's surface syntax 1:1 — no information has been lost, but nothing has been resolved yet.

### 5.1 Top‑level

```swift
public struct ABCFile {
    public let versionLine: VersionLine?
    public let fileHeader: FileHeader?
    public let elements: [ABCFileElement]   // tunes, freeText, typesetText, comments
    public let source: SourceRange
}

public enum ABCFileElement {
    case tune(ABCTune)
    case freeText(String, SourceRange)
    case typesetText(TextDirective, SourceRange)
    case stylesheetDirective(StylesheetDirective)
    case commentLine(String, SourceRange)
}

public struct FileHeader {
    public let fields: [InformationField]              // ordered, with originals preserved
    public let directives: [StylesheetDirective]       // interleaved with fields per source
    public let source: SourceRange
}

public struct ABCTune {
    public let header: TuneHeader
    public let body: TuneBody?            // optional per §2.2.1 (header-only tunes are legal)
    public let source: SourceRange
}
```

### 5.2 Tune header

`TuneHeader` is a typed projection of the information‑field table in §3 of the standard. Each field has a sum‑type variant carrying its parsed payload:

```swift
public enum InformationField {
    case reference(Int, SourceRange)                          // X:
    case title(TextString, SourceRange)                       // T:
    case composer(TextString, SourceRange)                    // C:
    case origin([String], SourceRange)                        // O: (semicolon-split)
    case area(TextString, SourceRange)                        // A: (deprecated)
    case book(TextString, SourceRange)                        // B:
    case discography(TextString, SourceRange)                 // D:
    case fileURL(URL?, SourceRange)                           // F:
    case group(TextString, SourceRange)                       // G:
    case history([TextString], SourceRange)                   // H: (continuations -> entries)
    case notes(TextString, SourceRange)                       // N:
    case source(TextString, SourceRange)                      // S:
    case transcription(TextString, SourceRange)               // Z:
    case rhythm(TextString, SourceRange)                      // R:

    case meter(MeterSpec, SourceRange)                        // M:
    case unitNoteLength(Fraction, SourceRange)                // L:
    case tempo(TempoSpec, SourceRange)                        // Q:
    case parts(PartsSpec, SourceRange)                        // P:
    case key(KeySpec, SourceRange)                            // K:
    case voice(VoiceSpec, SourceRange)                        // V:
    case userDefined(UserSymbol, SourceRange)                 // U:
    case macro(MacroSpec, SourceRange)                        // m:
    case symbolLine(SymbolSequence, SourceRange)              // s:
    case wordsAligned(LyricLine, SourceRange)                 // w:
    case wordsTrailing(TextString, SourceRange)               // W:
    case instruction(Instruction, SourceRange)                // I:
    case remark(String, SourceRange)                          // r:

    case unknown(FieldId, RawPayload, SourceRange)            // not in §3 — diagnostic, not fatal
}
```

`InformationField.unknown` is required: §3 mandates that unrecognised field identifiers be ignored with a non‑fatal warning, and we represent that by preserving the raw payload.

### 5.3 Tune body — syntactic shape

```swift
public struct TuneBody {
    public let lines: [BodyLine]
    public let source: SourceRange
}

public enum BodyLine {
    case music(MusicLine)
    case fieldChange(InformationField)        // inline-equivalent of K:, M:, L:, V:, etc.
    case lyricAligned(LyricLine, SourceRange) // w:
    case symbolLine(SymbolSequence, SourceRange) // s:
    case directive(StylesheetDirective)
    case commentLine(String, SourceRange)
}

public struct MusicLine {
    public let elements: [MusicElement]   // single logical line, possibly continuation-joined
    public let scoreLineBreak: ScoreLineBreak  // see §6.5
    public let source: SourceRange
}

public indirect enum MusicElement {
    case note(NoteToken)
    case rest(RestToken)
    case chord([NoteToken], lengthMultiplier: Fraction, SourceRange)
    case grace(GraceGroup)
    case tuplet(TupletSpec, [MusicElement], SourceRange)
    case slurOpen(SourceRange)
    case slurClose(SourceRange)
    case tie(SourceRange)
    case barLine(BarToken, SourceRange)
    case decoration(DecorationToken, SourceRange)
    case chordSymbol(String, SourceRange)
    case annotation(AnnotationPosition, TextString, SourceRange)
    case inlineField(InformationField, SourceRange)
    case overlay(SourceRange)                       // &
    case spacer(Int, SourceRange)                   // y
    case userSymbol(Character, SourceRange)         // pre-expansion
    case macroInvocation(MacroSpec, [MusicElement], SourceRange)
    case unknown(Token, SourceRange)
}
```

`NoteToken` is the raw note, not yet resolved against the active key signature:

```swift
public struct NoteToken {
    public let letter: Character                // C..B, c..b
    public let accidental: AccidentalToken?     // ^, ^^, =, _, __, ^k/n, _k/n  (k,n are Int)
    public let octaveAdjustment: Int            // sum of ' (+1) and , (-1)
    public let length: NoteLength
    public let brokenRhythmBefore: BrokenRhythm?
    public let brokenRhythmAfter: BrokenRhythm?
    public let tiesOut: Bool
    public let source: SourceRange
}

public struct NoteLength {
    public let multiplier: Int            // 1 if omitted
    public let divisor: Int               // 1 if omitted, doubled for each / without a number
    public var fraction: Fraction { Fraction(numerator: multiplier, denominator: divisor) }
}
```

### 5.4 Inline fields

An inline field (`[K:G]`, `[I:linebreak <none>]`, etc.) becomes a `MusicElement.inlineField` whose payload is the same `InformationField` enum as in the header. The semantic pass treats it as a state change point.

### 5.5 Construct order on a note (§4.20)

The standard fixes the order of prefixes and postfixes around a single note:

```
<grace notes> <chord symbols> <annotations>/<decorations> <accidentals> <note> <octave> <note length>
```

…plus a trailing tie `-`. The music parser enforces this order. Out‑of‑order constructs (e.g. `^C"chord"` instead of `"chord"^C`) produce a `Diagnostic.warning` with code `.constructOutOfOrder` but are accepted: the parser attempts to assemble a sensible `NoteToken` from whichever pieces it sees, in order to be tolerant of in‑the‑wild ABC. Strict mode (§8.3) escalates the warning to an error.

For chords, the bracket pair `[ … ]` substitutes for `<note>`; the same prefix/postfix slots apply to the entire bracketed group, except that accidentals attach to individual interior notes (per §4.17). Length multipliers inside *and* outside the chord are multiplied — `[C2E2G2]3` equals `[CEG]6` — and the chord's duration defaults to the duration of the first note if interior durations differ. Unisons (`[DD]`, repeated identical pitches) are preserved as a distinct case so renderers can draw the single‑stem / two‑note‑heads form.

### 5.6 Reserved characters in music code (§8.1)

The characters `# * ; ? @` are reserved inside music code for future ABC versions. When they appear "inside or between note groups" the parser treats them as `Token.unknown` and emits a `Diagnostic.info` (code `.reservedCharacter`). They are *not* dropped silently — preserving them in the token stream lets downstream tools warn the user. Reserved characters inside text strings, annotations, chord symbols and information‑field payloads are not affected; they pass through untouched.

The example from §8.1, `@a !pp! #bc2/3* [K:C#] de?f "@this $2was difficult to parse?" y |**`, must parse as the same sequence of musical events as `a !pp! bc2/3 [K:C#] def "@this $2was difficult to parse?" y |`. The conformance suite includes this case verbatim.

### 5.7 Beams and tokenizer whitespace (§4.7)

Beaming is purely syntactic: a run of beamable note durations not separated by whitespace forms a beam group. Backticks (\`) between notes are ignored. The tokenizer therefore tracks two kinds of whitespace:

- `Token.whitespace(.beamBreaking)` — actual spaces/tabs between music elements.
- `Token.whitespace(.beamPreserving)` — runs of backticks.

The semantic pass walks consecutive notes and assigns `BeamState.start` / `.middle` / `.end` / `.single` based on durations (only durations < `unitNoteLength` can be beamed) and beam‑breaking whitespace. An inline field in the middle of a beam — explicitly permitted by §3.2 — does *not* break the beam.

### 5.8 Tie adjacency rule (§4.11)

A tie symbol `-` is bound to the immediately preceding note (or chord). It may be followed by whitespace but not preceded by it. The parser enforces this: a `-` not preceded by a note token or `]` chord‑close emits a `Diagnostic.error` (code `.danglingTie`) and is dropped. Conversely, `c4 -c4` is rejected even though it would otherwise look reasonable, matching the standard's explicit prohibition.

---

## 6. Domain model (semantic)

This is the layer most consumers of CeolKit should depend on. The semantic pass:

1. Applies file‑header defaults to every tune.
2. Resolves `L:`, `M:`, `Q:`, `K:`, `V:` state for every event in tune order.
3. Expands `U:` (redefinable symbols) and `m:` (macros, both static and transposing).
4. Resolves accidental scope within a bar (an accidental on the first `^c` in a bar applies to subsequent `c`s in that bar at the same octave, per common practice; ABC §4.2 + dialect rules).
5. Resolves clef / staff / transposition (§4.6, §13) on each voice.
6. Threads ties across notes and across bars, validates slur nesting, materialises tuplets with their `p:q:r` parameters.
7. Resolves `P:` part ordering into a playable / printable sequence.
8. Attaches `w:` lyric syllables to notes per alignment rules (§5).
9. Records every applicable `%%ceolkit:*` directive on the affected scope (see §7).

### 6.1 Top types

```swift
public struct Score {
    public let source: SourceRange
    public let dialect: Dialect
    public let creator: String?                  // I:abc-creator
    public let charset: String?                  // I:abc-charset
    public let tunes: [Tune]
    public let freeText: [TextBlock]
    public let typesetText: [TypesetText]
    public let diagnostics: [Diagnostic]         // all issues from all stages
}

/// Bibliographic fields from the tune header, kept separate from the primary
/// musical properties on `Tune` so they don't crowd the call site.
public struct TuneMetadata {
    public let composer: TextString?
    public let origin: [String]          // O: semicolon-split; empty if absent
    public let area: TextString?         // A: — deprecated but preserved
    public let book: TextString?
    public let discography: TextString?
    public let fileURL: URL?
    public let group: TextString?
    public let history: [TextString]     // H: continuations become separate entries
    public let notes: TextString?
    public let source: TextString?
    public let rhythm: TextString?
    public let transcription: TextString?
}

/// Resolved part play order from the `P:` field (§3.1.9).
/// Complex nested plans (parenthesised repeats) are deferred to v0.2;
/// in v0.1 only simple sequences are fully expanded.
public struct PartPlan {
    public let sequence: [PartLabel]
    public let source: SourceRange
}

public struct PartLabel: Hashable {
    public let letter: Character         // A–Z as written in P:
    public let source: SourceRange
}

/// A macro definition from an `m:` field.
/// Full macro expansion is deferred to v0.2; pattern and expansion are stored
/// verbatim so the semantic pass can record them without losing information.
public struct MacroDefinition {
    public let pattern: String           // left-hand side (e.g. `~G2`)
    public let expansion: String         // right-hand side (e.g. `{A}G2`)
    public let source: SourceRange
}

public struct Tune {
    public let reference: Int                    // X:
    public let titles: [TextString]              // T: (≥0; spec says "should" follow X:)
    public let metadata: TuneMetadata            // C, O, B, D, F, G, H, N, S, R, Z, ...
    public let key: KeySignature                 // K: at end of header — required
    public let meter: Meter                      // M: or default
    public let unitNoteLength: Fraction          // L: or default per §3.1.7
    public let tempo: Tempo?                     // Q:
    public let parts: PartPlan?                  // P:
    public let voices: [Voice]                   // ≥1; single-voice tunes have one synthetic voice
    public let userSymbols: [Character: Decoration]
    public let macros: [MacroDefinition]
    public let directives: [CeolKitDirectiveScope] // see §7
    public let source: SourceRange
}
```

### 6.2 Voices

A `Voice` is the central container. Single‑voice tunes have one implicit voice; multi‑voice tunes have one per `V:` plus the `V:*` "all voices" pseudo‑voice (used by `K:` and transposition).

```swift
/// Identifies a voice within a tune. The `.all` pseudo-voice (`*`) is used by `K:`
/// and transposition directives that apply across every voice simultaneously.
public enum VoiceId: Hashable {
    case named(String)   // "1", "soprano", "T1", etc.
    case all             // "*" — all-voices pseudo-voice
}

public enum StemDirection: Hashable {
    case up
    case down
    case auto            // default — renderer decides based on note position
}

/// Display and transposition settings from the `V:` field (§4.16).
/// The semantic pass resolves the active value for each property by merging
/// `V:` settings over `K:` settings over file-header defaults.
/// `VoiceProperties` holds the voice-level layer of that stack.
public struct VoiceProperties: Hashable {
    public let clef: ClefSpec
    public let transposition: Transposition
    public let staffProperties: StaffProperties
    public let name: String?             // nm= — printed at start of first system
    public let subname: String?          // snm= — printed at subsequent systems
    public let stemDirection: StemDirection
    public let middleNote: PitchClass?   // middle= — pitch on the middle staff line; nil = default
}

public struct Voice {
    public let id: VoiceId                       // "1", "soprano", etc.; "*" for all-voice
    public let properties: VoiceProperties       // clef, stafflines, transpose, name, subname, …
    public let staves: [Staff]                   // usually 1; > 1 for grand staff voices
    public let directives: [CeolKitDirectiveScope]
    public let source: SourceRange
}

/// A secondary voice overlaid on the same staff via the `&` operator (§7.4).
/// Full voice overlay support is deferred to v0.2.
public struct VoiceOverlay {
    public let measures: [Measure]
    public let source: SourceRange
}

public struct Staff {
    public let measures: [Measure]               // bar-line-delimited
    public let overlays: [VoiceOverlay]          // & overlays per §7.4 of the standard
}

public struct Measure {
    public let openingBar: BarLine?              // bar before first event (e.g. anacrusis end)
    public let events: [Event]                   // notes, rests, chords, grace groups, ties, …
    public let closingBar: BarLine               // bar at end; may carry repeat info
    public let endingNumber: [Int]?              // |1, |2, [1,2 variant endings
    public let source: SourceRange
}
```

### 6.3 Events

`Event` is the unit a renderer iterates over within a measure. Every event has a resolved duration in terms of the unit note length and a resolved pitch where applicable.

```swift
public enum Event {
    case note(Note)
    case rest(Rest)
    case chord(Chord)            // unison / vertical chord — all notes share duration
    case grace(GraceGroup)       // attached to the following event
    case tuplet(Tuplet)
    case spacer(Spacer)
    case directiveAnchor(CeolKitDirective)   // a directive whose effect attaches to next event
}

public struct Note {
    public let pitch: Pitch                // diatonic + chromatic resolved
    public let writtenAccidental: Alteration? // what was actually printed in source
    public let displayedAccidental: Alteration? // what should be printed (after key sig & bar scope)
    public let duration: Fraction          // multiplied by unitNoteLength to get a whole-note fraction
    public let ties: TieState              // .none / .startsTie / .continuesTie / .endsTie
    public let slurs: SlurState            // open count, close count
    public let decorations: [Decoration]
    public let chordSymbol: ChordSymbol?
    public let annotations: [Annotation]
    public let beam: BeamState             // .start / .middle / .end / .single
    public let lyric: LyricSyllable?       // alignment from w: lines
    public let source: SourceRange
}

public enum DiatonicStep: Int, CaseIterable, Hashable, Comparable {
    case c = 0
    case d = 1
    case e = 2
    case f = 3
    case g = 4
    case a = 5
    case b = 6
}

public struct Pitch: Hashable {
    public let step: DiatonicStep          // .c .d .e .f .g .a .b
    public let alteration: Alteration      // exact, rational; see below
    public let octave: Int                 // scientific-pitch-notation octave (middle C = 4)
}

/// A pitch class: letter + alteration without an octave.
/// Used wherever octave is irrelevant — key signature tonic, chord symbol root, slash-chord bass.
public struct PitchClass: Hashable {
    public let step: DiatonicStep
    public let alteration: Alteration      // .natural for plain letters; .sharp / .flat for # / b
}

/// A semitone offset from the natural form of the diatonic step.
///
/// Stored as `numerator / denominator` (both `Int`) and *always* normalised so
/// that `denominator > 0` and `gcd(|numerator|, denominator) == 1`. This is
/// lossless: the `^k/n` written in ABC source survives unchanged into the
/// model and back out to the renderer's glyph table.
///
///   ^C           -> Alteration(numerator:  1, denominator: 1)
///   _C           -> Alteration(numerator: -1, denominator: 1)
///   ^^C          -> Alteration(numerator:  2, denominator: 1)
///   __C          -> Alteration(numerator: -2, denominator: 1)
///   =C / natural -> Alteration(numerator:  0, denominator: 1)
///   ^3/2C        -> Alteration(numerator:  3, denominator: 2)  // three-quarter sharp
///   _1/2C        -> Alteration(numerator: -1, denominator: 2)  // quarter flat
///
/// Common values are provided as static members for ergonomics:
///   .natural, .sharp, .flat, .doubleSharp, .doubleFlat,
///   .quarterSharp, .quarterFlat, .threeQuarterSharp, .threeQuarterFlat
public struct Alteration: Hashable {
    public let numerator: Int
    public let denominator: Int            // > 0, post-reduction
}

```

Note specifically:

- `writtenAccidental` is what was printed in the ABC. `displayedAccidental` is what a renderer should draw after applying the key signature and intra‑bar accidental memory. These will *differ* for the second `c` after a `^c` in C major, for example.
- Both `writtenAccidental` and `displayedAccidental` are typed as `Alteration?` — the field names already convey the display-vs-pitch distinction; a separate `Accidental` typealias would only add confusion.
- `duration` is normalised. The original `NoteLength` (with its raw multiplier/divisor and broken‑rhythm operator) is preserved in `Note.source` for round‑trip purposes via the AST, but consumers should not have to re‑interpret it.

```swift
public struct Rest {
    public let kind: RestKind
    public let duration: Fraction        // in unit note lengths; same normalisation as Note.duration
    public let decorations: [Decoration]
    public let source: SourceRange
}

public enum RestKind {
    case normal               // z — visible, counts duration
    case invisible            // x — invisible, counts duration
    case fullMeasure          // Z — visible whole-bar rest
    case fullMeasureInvisible // X — invisible whole-bar rest
}

/// A vertical group of simultaneous notes. All notes share the same duration.
/// The chord as a whole participates in beaming, slurring, and tying.
public struct Chord {
    public let notes: [Note]             // ≥2; each Note.duration equals Chord.duration
    public let duration: Fraction
    public let decorations: [Decoration]
    public let chordSymbol: ChordSymbol?
    public let annotations: [Annotation]
    public let beam: BeamState
    public let ties: TieState
    public let slurs: SlurState
    public let lyric: LyricSyllable?
    public let source: SourceRange
}

/// A pre-beat ornament attached to the following event.
/// v0.1 preserves the structural distinction between grace kinds;
/// full rhythmic timing is deferred to v0.2.
public struct GraceGroup {
    public let kind: GraceKind
    public let notes: [Note]             // durations nominal; timing resolved by renderer
    public let source: SourceRange
}

public enum GraceKind {
    case acciaccatura    // {/  — crushed grace, typically slurred and crossed
    case appoggiatura    // {   — leaning grace
}

/// The semantic form of a `(p:q:r` tuplet after the semantic pass has resolved
/// and validated the group. The semantic pass fills `q` and `r` from the
/// standard-specified defaults when they are omitted in source.
public struct Tuplet {
    public let p: Int          // notes played…
    public let q: Int          // …in the time of q normal notes
    public let r: Int          // total notes in the group (equals p when r is omitted)
    public let events: [Event]
    public let source: SourceRange
}

/// A visual spacer (`y`, `y2`, …). Has no musical duration.
public struct Spacer {
    public let width: Int      // 1 for bare y; explicit number for y2, y4, etc.
    public let source: SourceRange
}

/// The resolved, normalised form of a decoration after the semantic pass.
/// Short-form decorations (`. ~ H L M O P S T u v`) are expanded to their
/// canonical cases during the semantic pass; consumers see only this type.
public enum Decoration: Hashable {

    // Dynamics
    case ppp                    // !ppp!
    case pp                     // !pp!
    case p                      // !p!
    case mp                     // !mp!
    case mf                     // !mf!
    case f                      // !f!
    case ff                     // !ff!
    case fff                    // !fff!
    case sfz                    // !sfz!

    // Articulations
    case staccato               // !staccato! / .
    case staccatissimo          // !staccatissimo!
    case tenuto                 // !tenuto!
    case accent                 // !accent! / L
    case strongAccent           // !>!
    case arpeggio               // !arpeggio!

    // Ornaments
    case trill                  // !trill! / T
    case trillStart             // !trill(!
    case trillEnd               // !trill)!
    case mordent                // !mordent! / M
    case pralltriller           // !pralltriller! / P
    case roll                   // !roll! / ~
    case turn                   // !turn!
    case invertedTurn           // !invertedturn!

    // Fermatas
    case fermata                // !fermata! / H
    case invertedFermata        // !invertedfermata!

    // Bowing / technique
    case upbow                  // !upbow! / u
    case downbow                // !downbow! / v
    case open                   // !open!
    case snap                   // !snap!
    case thumb                  // !thumb!
    case plus                   // !+!  (left-hand pizzicato / stopped horn)
    case fingering(Int)         // !0! … !5!

    // Hairpins (single-event anchors)
    case crescendoStart         // !<(!
    case crescendoEnd           // !<)!
    case decrescendoStart       // !>(!
    case decrescendoEnd         // !>)!

    // Navigation / repeat signs
    case segno                  // !segno! / S
    case coda                   // !coda! / O
    case fine                   // !fine!
    case dacapo                 // !D.C.!
    case dacapoAlFine           // !D.C.al Fine!
    case dacapoAlCoda           // !D.C.al Coda!
    case dalsegno               // !D.S.!
    case dalsegnoAlFine         // !D.S.al Fine!
    case dalsegnoAlCoda         // !D.S.al Coda!

    // Breath / pause
    case breath                 // !breath!
    case caesura                // !caesura!

    // Forward compatibility — any !name! not in this table, preserved verbatim
    case unknown(String)
}
```

Short-form expansion happens in the semantic pass. By the time a `Note`, `Rest`, or `Chord` reaches a consumer, all short-form characters (`.`, `~`, `H`, etc.) have been replaced with their corresponding `Decoration` case. `Tune.userSymbols` maps `U:` characters to `Decoration` values by the same mechanism.

```swift
/// A harmony symbol written in double quotes above the staff (e.g. `"Gm7"`, `"C/E"`).
/// `root` and `bassNote` are structured for transposition; `quality` is kept verbatim
/// because chord quality vocabulary is not standardised.
public struct ChordSymbol: Hashable {
    public let root: PitchClass          // e.g. G in "Gm7"
    public let quality: String           // e.g. "m7"; empty string for plain major
    public let bassNote: PitchClass?     // slash-chord bass, e.g. E in "C/E"
    public let raw: String               // verbatim text between the quotes
    public let source: SourceRange
}

/// A text annotation attached to a note or chord, written in double quotes with a
/// position-prefix character (e.g. `"^above"`, `"_below"`).
/// Distinct from `ChordSymbol`, which starts with a note letter (A–G).
/// `AnnotationPosition` is defined in the model and reused by the syntactic AST.
public struct Annotation: Hashable {
    public let position: AnnotationPosition
    public let text: TextString
    public let source: SourceRange
}

public enum AnnotationPosition: Hashable {
    case above                           // ^
    case below                           // _
    case left                            // <
    case right                           // >
    case absolute(x: Double, y: Double)  // @x,y  (staff-space coordinates)
}

/// Counts of slur marks opening and closing at a note or chord.
/// A struct of two counts rather than an enum because slurs nest — multiple slurs
/// can be simultaneously active, and a single note can open or close several at once
/// (e.g. the first note in `((cde))` has `opens: 2`).
/// The semantic pass validates nesting per §6 step 6 and emits a diagnostic for
/// unmatched slur marks.
public struct SlurState: Hashable {
    public let opens: Int    // slurs beginning at this note
    public let closes: Int   // slurs ending at this note

    public static let none = SlurState(opens: 0, closes: 0)
}

/// Assigned by the semantic pass. Ties may span barlines (§6 step 6).
/// A note in the middle of a chain (e.g. the second note in `C4-C4-C4`) uses
/// `.continuesTie` — it both receives the tie from the previous note and passes it forward.
public enum TieState: Hashable {
    case none            // not part of a tie
    case startsTie       // tied forward only (first note of a chain)
    case continuesTie    // tied both backward and forward (mid-chain)
    case endsTie         // tied backward only (last note of a chain)
}

/// Assigned by the semantic pass per §5.7.
/// Only notes with duration < unitNoteLength are beamable; all others are `.single`.
/// An inline field in the middle of a beam group does not break the beam.
public enum BeamState: Hashable {
    case start    // first note in a beamed group
    case middle   // interior note in a beamed group
    case end      // last note in a beamed group
    case single   // not beamed (duration ≥ unitNoteLength, or isolated beamable note)
}

/// The lyric alignment attached to a note by the semantic pass from `w:` lines (§6 step 8).
///
/// `Note.lyric == nil` means no `w:` line applies or the line is exhausted (see §10
/// open question 5). `.skip` means a `w:` line exists but explicitly passed over this
/// note with `*` — the two cases are semantically distinct.
public enum LyricSyllable: Hashable {
    /// A syllable with display text. `connection` tells the renderer whether to draw
    /// a hyphen connector to the next aligned note.
    case text(TextString, connection: LyricConnection)

    /// `_` — this note extends the previous syllable; renderer draws an extender line.
    case melisma

    /// `*` — this note is explicitly skipped; no text or extender is drawn.
    case skip
}

public enum LyricConnection: Hashable {
    case wordEnd    // syllable ends a word; no connector
    case hyphen     // mid-word; renderer draws a hyphen to the next syllable
}
```

### 6.4 Key, meter, tempo

```swift
/// The modal quality of a key signature. Church modes share names with `.major` (Ionian)
/// and `.minor` (Aeolian) but are listed explicitly so callers never need string comparison.
/// `.none` corresponds to `K:none` (no key signature, all naturals).
/// `.highlandPipes` and `.highlandPipesNoSignature` correspond to `K:HP` and `K:Hp`.
public enum Mode: Hashable {
    case major
    case minor
    case ionian
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case aeolian
    case locrian
    case none                    // K:none — no key signature
    case highlandPipes           // K:HP  — F# and C# implicit, not drawn on staff
    case highlandPipesNoSignature // K:Hp  — no sharps drawn
}

/// An explicit accidental modification applied to a diatonic step within a key signature
/// (e.g. the `^f` in `K:D Phr ^f`). Structurally identical to `PitchClass` but
/// semantically distinct: this is an instruction ("alter this step by this amount")
/// rather than a pitch name.
public struct KeyModification: Hashable {
    public let step: DiatonicStep
    public let alteration: Alteration
}

public enum Clef: Hashable {
    case treble
    case bass
    case baritone      // bass3 — F clef on line 3
    case alto          // C clef on line 3
    case tenor         // C clef on line 4
    case soprano       // C clef on line 1
    case mezzoSoprano  // C clef on line 2
    case percussion    // perc
    case none
}

/// The clef drawn on the staff plus an optional octave-transposition marker.
/// `octaveShift` stores the value as ABC writes it (0, ±8, ±15) so renderers can
/// draw the correct numeral on the clef glyph without reverse-engineering it from semitones.
public struct ClefSpec: Hashable {
    public let clef: Clef
    public let octaveShift: Int    // 0, ±8, ±15 as written in source (e.g. treble+8)
}

/// Written-vs-sounding pitch offset applied to a voice or staff (§13).
/// Covers `transpose=N` (chromatic semitones) and `octave=N` (whole-octave shift).
public struct Transposition: Hashable {
    public let semitones: Int    // chromatic transposition; 0 = none
    public let octave: Int       // additional octave shift; 0 = none

    public static let none = Transposition(semitones: 0, octave: 0)
}

/// Rendering hints attached to a voice or key field via `V:` / `K:` syntax.
/// Covers `stafflines=N` and `scale=N`.
public struct StaffProperties: Hashable {
    public let staffLines: Int     // default 5
    public let scale: Double?      // optional rendering scale factor; nil = default
}

public struct KeySignature {
    public let tonic: PitchClass?          // nil for K:none and K:HP
    public let mode: Mode
    public let modifications: [KeyModification]  // K:D Phr ^f
    public let explicit: Bool              // K: ... exp ...
    public let clef: ClefSpec              // resolved
    public let transposition: Transposition // resolved
    public let staffProperties: StaffProperties
    public let source: SourceRange
}

public enum Meter {
    case fraction(num: Int, den: Int)
    case commonTime           // C  -> 4/4
    case cutTime              // C| -> 2/2
    case complex([Int], den: Int)  // (2+3+2)/8
    case free                 // M:none
}

public struct Tempo {
    public let prelude: TextString?
    public let beats: [Fraction]   // one or more beat units
    public let bpm: Double
    public let postlude: TextString?
}
```

### 6.5 Score line breaks

ABC v2.2 distinguishes a *code line‑break* (in the source) from a *score line‑break* (in the rendered output). The semantic model exposes the latter:

```swift
public enum ScoreLineBreak {
    case hard      // forces a system break in output
    case soft      // permits but does not force
    case suppressed // the source line ended with \
}
```

How code line‑breaks map to score line‑breaks depends on `I:linebreak` settings (`<EOL>`, `<none>`, `$`, `!`). The semantic pass resolves this so renderers don't have to.

---

## 7. CeolKit extensions

The three CeolKit `%%ceolkit:*` directives are first‑class participants in the domain model. They follow ABC v2.2 §11.5's *application‑specific directive* convention (`%%<app>:<directive>` — see the standard's example `%%noteedit:fontcolor blue`), so the line classifier recognises them generically as members of the `%%ceolkit:` namespace before dispatching to the typed handlers.

### 7.1 Representation

```swift
public enum CeolKitDirective: Hashable {
    case pipeFormat(Bool)              // %%ceolkit:pipeformat true|false
    case pageNumber(Int)               // %%ceolkit:pagenumber N  (N >= 1)
    case stemAlignment(Int)            // %%ceolkit:stemalignment N  (signed integer)
}

public struct CeolKitDirectiveScope {
    public let directive: CeolKitDirective
    public let scope: Scope
    public let source: SourceRange
}

public enum Scope {
    case fileGlobal           // file preamble
    case tuneGlobal           // tune header
    case voiceLocal(VoiceId)  // body, immediately after V:
}
```

`CeolKitDirectiveScope` values are attached to the smallest scope they affect: `Score.tunes[i].directives` for tune‑global, `Voice.directives` for voice‑local, and `Score`‑level (via a not‑yet‑named bag — see §10 open question) for file‑global. This mirrors the scope rules in `EXTENSIONS.md`.

### 7.2 Semantics that the parser enforces

The parser/semantic pass enforces what the extension document specifies:

- **`pipeFormat`**: last occurrence wins at file scope. Setting `false` after `true` cancels the earlier one. Caller's `ABCConverter.Options.bagpipeFormat = true` *cannot* be cancelled by the directive (this is enforced at the converter boundary, not the parser; the parser simply records what the file said).
- **`pageNumber`**: must be a positive integer ≥ 1. Out‑of‑range or non‑numeric arguments emit a `Diagnostic.warning` and the directive is dropped from the model.
- **`stemAlignment`**: signed integer; `0` resets to default. Voice‑local scope requires that the directive immediately follow a `V:` line in the body. Validation of that placement is the parser's job; producing a warning when it appears elsewhere is also the parser's job.

### 7.3 Extension point for future directives

The extension is modelled as an enum rather than a string map so adding a new directive is a deliberate breaking change. To allow forward compatibility:

```swift
public enum CeolKitDirective: Hashable {
    // …known cases…
    case unknown(name: String, payload: String)   // anything %%ceolkit:* not yet defined
}
```

`unknown` is what users get for `%%ceolkit:foobar 3`; it's preserved verbatim so downstream tools (or a later library version) can still see it.

---

## 8. Error model

### 8.1 Diagnostics

```swift
public struct Diagnostic {
    public enum Severity { case error, warning, info }
    public let severity: Severity
    public let code: DiagnosticCode      // stable identifier, e.g. .invalidPageNumber, .unknownField
    public let message: String           // human-readable
    public let source: SourceRange
    public let related: [SourceRange]    // e.g. earlier definition for a duplicate
    public let hint: String?             // optional fix suggestion
}
```

`DiagnosticCode` is an enum (not a string) so it's exhaustive and stable across versions. Every parser warning has a code; consumers can suppress codes selectively without grepping messages.

### 8.2 Strict + recoverable contract

The parser **always returns a `Score`**, even on error, unless the input is fundamentally undecodable as text. The shape of the contract:

```swift
public struct ParseResult {
    public let score: Score              // always present; may be partial
    public let diagnostics: [Diagnostic] // empty iff fully clean
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

public protocol ABCParser {
    func parse(_ source: String, options: ParseOptions) -> ParseResult
}

public struct ParseOptions {
    public var dialectOverride: Dialect?         // ignore version line if set
    public var maxDiagnostics: Int               // stop collecting after N (default: unbounded)
    public var unknownExtensionPolicy: UnknownExtensionPolicy   // .preserve / .warn / .drop
    public var strictRecovery: Bool              // if true, stop parsing the current tune at first error
}
```

Recovery strategy by stage:

- **Lexer**: emit `Token.unknown(Character, …)` for an unrecognised character; continue.
- **Line classifier**: an unparseable line becomes `LogicalLine.freeText` with a warning. The standard explicitly permits this for HTML or email headers in tunebook files (§2.2.3).
- **Field parser**: a malformed field payload produces `InformationField.unknown` and a diagnostic; downstream code treats the field as absent for semantic purposes (so e.g. a malformed `M:` falls back to the default meter rather than crashing).
- **Music parser**: a malformed element becomes `MusicElement.unknown(Token, …)`; bar boundaries serve as resync points.
- **Semantic pass**: a missing required field (e.g. no `K:`) produces an error diagnostic, but a `Tune` is still produced with a synthetic default `KeySignature` so renderers downstream see a well‑formed shape.

This is exactly the contract editor tooling needs: never lose a structural anchor, never silently drop content, always tell the caller *why*.

### 8.3 Strict mode

When `ParseOptions.strictRecovery == true`, the first error in a tune marks the remainder of that tune as `Tune.partial = true` and the parser drops body content after the error point. The `Score` still contains the other tunes parsed cleanly. This is intended for batch validators and round‑trip tests.

---

## 9. Public Swift API surface

The public types the rest of CeolKit (and external consumers) depend on:

```swift
public protocol ABCParser {
    func parse(_ source: String, options: ParseOptions) -> ParseResult
    func parse(_ source: String, options: ParseOptions, dialectHint: Dialect?) -> ParseResult
}

public struct CeolKitParser: ABCParser { /* default impl */ }
```

Submodules:

```
CeolKit/
  Source/
    SourceRange.swift
  Parser/
    Lexer/
    LineClassifier.swift
    Tokens/
    AST/
    Fields/                // one file per field type
    Semantic/              // state manager, accidental scoping, voice resolution
    Diagnostics/
  Model/                   // the §6 domain types
  Extensions/              // §7 directive parsing + scoping
  Tests/
    Conformance/           // every example in v2.2 §14
    Extensions/
    Recovery/              // malformed inputs that must still produce a Score
```

Every type in `Model/` is `Sendable` and `Codable`. The model has no reference cycles — `Score` is a tree. Source ranges are values; URLs are optional. This makes the model trivially serialisable to JSON, which is useful for back‑ends written in other languages.

---

## 10. Open questions

These are the things I'd push to a v0.2 of this spec rather than guessing now:

1. **File‑global directive bag.** §7.1 mentions attaching file‑global `%%ceolkit:*` directives somewhere on `Score`. Two viable shapes: a flat `[CeolKitDirectiveScope]` on `Score`, or a dedicated `FilePreamble` struct that also captures `I:abc-charset`, `I:abc-creator`, etc. The latter is cleaner if we expect more global state to arrive.
2. **Macro expansion timing.** Should `m:` macros be expanded eagerly during the semantic pass (so consumers see only resolved notes), or kept as `Event.macroExpansion` nodes whose children are the expansion? Eager is simpler; lazy preserves source intent for editor tooling. Recommendation: eager by default, with an option to retain the wrapper.
3. **MIDI / playback hints.** abcm2ps and abc2midi have a swarm of `%%MIDI` directives. None of those are in `EXTENSIONS.md`'s CeolKit fork additions, but CeolKit presumably needs to pass them through. Suggest a `case passthrough(name: String, payload: String)` on `StylesheetDirective` so they survive untouched.
4. **Unicode normalisation in lyrics.** Aligned lyrics (`w:`) use `-`, `_`, `*`, `~`, `|` with special meanings. Recommend NFC‑normalising lyric strings before alignment is computed, so visually identical syllables compare equal.
5. **Lyric alignment ambiguity.** When `w:` is shorter than the number of notes since the last bar, the standard says to align as many as given and leave the rest blank. When it's longer, behaviour differs across implementations. Pick the strict v2.2 reading and surface a diagnostic for the over‑long case.

### Resolved (recorded here for the changelog)

- **Microtonal accidentals — resolved.** `Pitch.alteration` is a rational `Alteration(numerator: Int, denominator: Int)`, normalised. Floating point is rejected: a quarter‑sharp is `1/2`, a three‑quarter‑sharp is `3/2`, etc. — exact, hashable, and structurally identical to what the renderer eventually has to write on the staff.

---

## 11. What ships in v0.1

A reasonable first cut to validate the architecture without trying to be exhaustive:

- Stages 1–4 fully working: file structure, all v2.2 information fields, line continuation, comments, stylesheet directives, inline fields.
- Music parser: pitches, octaves, accidentals (including microtonal rational accidentals), length, broken rhythm, rests, bar lines, repeat bars and variant endings, ties, slurs, chords, basic decorations (`!…!` and short‑form), chord symbols, annotations.
- Semantic pass: K/L/M/V/U resolution, accidental scoping within a bar, ties across bars, single‑voice tunes plus multi‑voice voice splitting.
- All three `%%ceolkit:*` extensions parsed and scope‑validated.
- Strict + recoverable diagnostics with stable codes.
- Test suite over the four §14 sample tunes plus a malformed‑input recovery suite.

Deferred to v0.2+:

- Grace notes with full rhythmic timing.
- `P:` part plans more complex than `P:A2`.
- Macros, both static and transposing.
- Voice overlay (`&`).
- Custom transposition for diatonic instruments (§13.4).
- Symbol lines (`s:`).

---

## 12. References

- *The DRAFT abc music notation standard 2.2* — Chris Walshaw, abcnotation.com/wiki/abc:standard:v2.2
- *CeolKit `EXTENSIONS.md`* — (this repository)
- RFC 2119 — keyword conventions used by the standard
