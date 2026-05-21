# CeolKit Domain Model Reference

Quick-load reference for the `CeolKitModel` types so subsequent sessions don't need to re-read every source file.

---

## Top-level hierarchy

```
Score
  ├── dialect: Dialect          (.strict(version:) | .loose)
  ├── creator: String?          (I:abc-creator)
  ├── charset: String?          (I:abc-charset)
  ├── tunes: [Tune]
  ├── freeText: [TextBlock]
  ├── typesetText: [TypesetText]
  └── diagnostics: [Diagnostic]

Tune
  ├── reference: Int            (X:)
  ├── titles: [TextString]      (T: — multiple allowed)
  ├── metadata: TuneMetadata    (C: O: A: B: D: F: G: H: N: S: R: Z:)
  ├── key: KeySignature         (K: — required, marks end of header)
  ├── meter: Meter              (M:)
  ├── unitNoteLength: Fraction  (L: — default: 1/8 if M≥3/4, else 1/16)
  ├── tempo: Tempo?             (Q:)
  ├── parts: PartPlan?          (P:)
  ├── voices: [Voice]           (≥1; single-voice tunes have one synthetic voice "1")
  ├── userSymbols: [Character: Decoration]
  ├── macros: [MacroDefinition]
  ├── directives: [CeolKitDirectiveScope]
  └── source: SourceRange

Voice
  ├── id: VoiceId               (String; "*" = all-voice)
  ├── properties: VoiceProperties
  ├── staves: [Staff]           (usually 1; >1 for grand staff)
  ├── directives: [CeolKitDirectiveScope]
  └── source: SourceRange

Staff
  ├── measures: [Measure]
  └── overlays: [VoiceOverlay]  (& overlays — v0.2+)

Measure
  ├── openingBar: BarLine?      (nil for anacrusis / first measure)
  ├── events: [Event]
  ├── closingBar: BarLine
  ├── endingNumber: [Int]?      (|1, |2, [1 variant endings)
  └── source: SourceRange
```

---

## Event enum

```swift
enum Event {
    case note(Note)
    case rest(Rest)
    case chord(Chord)           // vertical chord — all notes share duration
    case grace(GraceGroup)      // attached to following event
    case tuplet(Tuplet)
    case spacer(Spacer)
    case directiveAnchor(CeolKitDirective)
}
```

---

## Note

```swift
struct Note {
    let pitch: Pitch
    let writtenAccidental: Alteration?   // what was in ABC source (nil if none written)
    let displayedAccidental: Alteration? // what renderer should draw (nil if redundant)
    let duration: Fraction               // multiplier × unitNoteLength; C=1/1, C2=2/1, C/=1/2
    let ties: TieState                   // .none .startsTie .continuesTie .endsTie
    let slurs: SlurState                 // open/close counts
    let decorations: [Decoration]
    let chordSymbol: ChordSymbol?
    let annotations: [Annotation]
    let beam: BeamState                  // .start .middle .end .single
    let lyric: LyricSyllable?            // nil = no w: line applies
    let source: SourceRange
}
```

Key distinction: `writtenAccidental` ≠ `displayedAccidental`.
- Second `c` after `^c` in a bar: `writtenAccidental=nil`, `pitch.alteration=+1/1`, `displayedAccidental=nil`.
- `=f` in K:G: all three are `Alteration(0,1)` (must display natural to cancel key sig).
- Redundant `^f` in K:G: `writtenAccidental=+1/1`, `displayedAccidental=nil`.

---

## Pitch

```swift
struct Pitch: Hashable {
    let step: DiatonicStep   // .c .d .e .f .g .a .b
    let alteration: Alteration
    let octave: Int          // scientific notation; middle C (ABC lowercase 'c') = octave 4
}
```

**ABC octave mapping:**
- Uppercase `C–B` → octave 3  
- Lowercase `c–b` → octave 4 (middle C = c = C4)
- Each `'` raises octave by 1 (`c'` = octave 5)
- Each `,` lowers octave by 1 (`C,` = octave 2)

---

## Alteration

```swift
struct Alteration: Hashable {
    let numerator: Int
    let denominator: Int    // always > 0, always reduced
}
```

| ABC source | Alteration |
|------------|-----------|
| `^`        | (1, 1)    |
| `_`        | (-1, 1)   |
| `^^`       | (2, 1)    |
| `__`       | (-2, 1)   |
| `=`        | (0, 1)    |
| `^1/2`     | (1, 2)    |
| `_3/2`     | (-3, 2)   |

Natural from key signature (no written accidental) → `Alteration(0, 1)`.
Key-applied sharp/flat is stored in `pitch.alteration`, not `writtenAccidental`.

---

## Fraction (duration)

```swift
struct Fraction: Hashable {
    let numerator: Int
    let denominator: Int   // NOT reduced automatically — store as-is from source
}
```

Duration is relative to `unitNoteLength`:
| ABC notation | Fraction  |
|-------------|----------|
| `C`         | (1, 1)   |
| `C2`        | (2, 1)   |
| `C4`        | (4, 1)   |
| `C/`        | (1, 2)   |
| `C/2`       | (1, 2)   |
| `C//`       | (1, 4)   |
| `C3/2`      | (3, 2)   |

**Broken rhythm** (both notes share same base duration unless explicit length overrides):
| n `>` | first × | second × |
|-------|--------|---------|
| 1 (`>`)  | 3/2    | 1/2    |
| 2 (`>>`) | 7/4    | 1/4    |
| 3 (`>>>`)| 15/8   | 1/8    |

Formula: n chevrons → first × (2^(n+1)−1)/2^n, second × 1/2^n. Total preserved.
`<` reverses: first gets 1/2^n, second gets (2^(n+1)−1)/2^n.

---

## KeySignature

```swift
struct KeySignature {
    let tonic: PitchClass?          // nil for K:none and K:HP/K:Hp
    let mode: Mode
    let modifications: [KeyModification]  // K:D Phr ^f
    let explicit: Bool              // K: ... exp ...
    let clef: ClefSpec
    let transposition: Transposition
    let staffProperties: StaffProperties
    let source: SourceRange
}
```

**K: field parsing rules:**
- `K:none` → `tonic=nil, mode=.none`
- `K:HP` → `tonic=nil, mode=.highlandPipes`
- `K:Hp` → `tonic=nil, mode=.highlandPipesNoSignature`
- `K:C`, `K:G`, etc. → letter [b|#] [mode] [clef] [modifications...]
- Accidentals in K: use `b` (flat) and `#` (sharp), NOT `_` and `^`
- Mode abbreviations (case-insensitive, ≥3 chars): `maj` `min` `ion` `dor` `phr` `lyd` `mix` `aeo` `loc`; `m` alone = minor

**Key signature sharps/flats per mode** (number of sharps, + = sharp, − = flat):

| Key | Sharps/Flats |
|-----|-------------|
| C maj / A min | 0 |
| G maj | +1 (F#) |
| D maj | +2 (F#, C#) |
| A maj | +3 |
| E maj | +4 |
| B / Cb maj | +5 / -7 |
| F# / Gb maj | +6 / -6 |
| F maj | -1 (Bb) |
| Bb maj | -2 |
| Eb maj | -3 |
| Ab maj | -4 |
| Db maj | -5 |

---

## Mode enum

```swift
enum Mode: Hashable {
    case major, minor, ionian, dorian, phrygian, lydian,
         mixolydian, aeolian, locrian
    case none              // K:none
    case highlandPipes     // K:HP — F# and C# implicit
    case highlandPipesNoSignature  // K:Hp
}
```

**Important:** Use `Mode.none` explicitly (not `.none`) to avoid Optional ambiguity.

---

## Meter enum

```swift
enum Meter {
    case fraction(num: Int, den: Int)
    case commonTime          // C → 4/4
    case cutTime             // C| → 2/2
    case complex([Int], den: Int)   // (2+3)/8
    case free                // M:none
}
```

Meter does NOT conform to Equatable — use pattern matching in tests.

**Default unitNoteLength from meter:**
- M ≥ 3/4 (numerically) → L = 1/8
- M < 3/4 → L = 1/16
- C (commonTime) → 4/4 ≥ 3/4 → L = 1/8
- C| (cutTime) → 2/2 ≥ 3/4 → L = 1/8

---

## BarLine / BarLineKind

```swift
struct BarLine: Hashable { let kind: BarLineKind; let source: SourceRange }

enum BarLineKind: Hashable {
    case single    // |
    case double    // ||
    case final     // |]
    case start     // [|
    case dotted    // .|
    case repeatEnd    // :|
    case repeatStart  // |:
    case repeatBoth   // ::
}
```

---

## Rest / RestKind

```swift
struct Rest { let kind: RestKind; let duration: Fraction; let decorations: [Decoration]; let source: SourceRange }

enum RestKind {
    case normal           // z
    case invisible        // x
    case fullMeasure      // Z
    case fullMeasureInvisible  // X
}
```

---

## Tuplet

```swift
struct Tuplet {
    let p: Int      // notes played…
    let q: Int      // …in time of q normal notes
    let r: Int      // total notes in group
    let events: [Event]
    let source: SourceRange
}
```

Standard defaults (§4.12):
- `(2` → p=2, q=3, r=2 (duplet in 3/4)
- `(3` → p=3, q=2, r=3 (triplet)
- `(4` → p=4, q=3, r=4
- `(5` → p=5, q=2 (or 3 in 3/4), r=5
- `(6` → p=6, q=2, r=6
- `(7` → p=7, q=2 (or 3), r=7
- `(8` → p=8, q=3, r=8
- `(9` → p=9, q=2, r=9
- Explicit: `(p:q:r`

---

## BeamState / TieState / SlurState

```swift
enum BeamState: Hashable { case start, middle, end, single }
enum TieState: Hashable  { case none, startsTie, continuesTie, endsTie }
struct SlurState: Hashable { let opens: Int; let closes: Int }
```

Beam rules:
- Notes with duration < beat are beamable (beat = time sig numerator unit)
- Adjacent beamable notes without whitespace form a group
- First in group → `.start`; middle → `.middle`; last → `.end`; alone → `.single`
- Non-beamable or whitespace-separated → `.single`

---

## LyricSyllable / LyricConnection

```swift
enum LyricSyllable: Hashable {
    case text(TextString, connection: LyricConnection)
    case melisma     // _ — extends previous syllable
    case skip        // * — explicitly skip this note
}
// nil lyric = w: line exhausted or absent (distinct from .skip)

enum LyricConnection: Hashable {
    case wordEnd   // end of word; no connector drawn
    case hyphen    // mid-word; draw hyphen to next syllable
}
```

`w:` alignment tokens:
- space/hyphen-separated syllables align to notes in order
- `-` = hyphen connection (mid-word, next note gets continuation)
- `_` = melisma (extends current syllable)
- `*` = explicit skip
- `|` = bar reset (re-aligns at next bar)
- `~` = word-linking space (rendered as no-space)

---

## Decoration enum (selected cases)

```swift
enum Decoration: Hashable {
    // Dynamics: .ppp .pp .p .mp .mf .f .ff .fff .sfz
    // Articulations: .staccato .staccatissimo .tenuto .accent .strongAccent .arpeggio
    // Ornaments: .trill .trillStart .trillEnd .mordent .pralltriller .roll .turn .invertedTurn
    // Fermatas: .fermata .invertedFermata
    // Bowing: .upbow .downbow .open .snap .thumb .plus
    case fingering(Int)        // !0! … !5!
    // Hairpins: .crescendoStart .crescendoEnd .decrescendoStart .decrescendoEnd
    // Navigation: .segno .coda .fine .dacapo .dacapoAlFine .dacapoAlCoda
    //             .dalsegno .dalsegnoAlFine .dalsegnoAlCoda
    // Breath: .breath .caesura
    case unknown(String)       // forward compatibility
}
```

Short-form expansions (resolved by semantic pass):
| Char | Decoration |
|------|-----------|
| `.`  | .staccato |
| `~`  | .roll |
| `H`  | .fermata |
| `L`  | .accent |
| `M`  | .mordent |
| `O`  | .coda |
| `P`  | .pralltriller |
| `S`  | .segno |
| `T`  | .trill |
| `u`  | .upbow |
| `v`  | .downbow |

---

## Chord (vertical / unison)

```swift
struct Chord {
    let notes: [Note]     // ≥2; each Note.duration == Chord.duration
    let duration: Fraction
    let decorations: [Decoration]
    let chordSymbol: ChordSymbol?
    let annotations: [Annotation]
    let beam: BeamState
    let ties: TieState
    let slurs: SlurState
    let lyric: LyricSyllable?
    let source: SourceRange
}
```

ABC syntax: `[CEG]2` — all notes share the bracket's duration.

---

## GraceGroup

```swift
struct GraceGroup { let kind: GraceKind; let notes: [Note]; let source: SourceRange }
enum GraceKind { case acciaccatura; case appoggiatura }
// {/notes} = acciaccatura; {notes} = appoggiatura
// Grace note durations are nominal; timing resolved by renderer
```

---

## Clef / ClefSpec

```swift
struct ClefSpec: Hashable { let clef: Clef; let octaveShift: Int }
enum Clef: Hashable {
    case treble, bass, baritone, alto, tenor, soprano, mezzoSoprano, percussion, none
}
// K:G clef=bass → ClefSpec(clef: .bass, octaveShift: 0)
// K:C treble+8  → ClefSpec(clef: .treble, octaveShift: 8)
```

---

## VoiceProperties

```swift
struct VoiceProperties: Hashable {
    let clef: ClefSpec
    let transposition: Transposition   // semitones, octave
    let staffProperties: StaffProperties  // staffLines (default 5), scale
    let name: String?         // nm= — first system label
    let subname: String?      // snm= — subsequent system label
    let stemDirection: StemDirection
    let middleNote: PitchClass?  // middle= pitch on middle staff line
}
```

---

## Annotation / AnnotationPosition

```swift
struct Annotation: Hashable { let position: AnnotationPosition; let text: TextString; let source: SourceRange }
enum AnnotationPosition: Hashable {
    case above           // "^text"
    case below           // "_text"
    case left            // "<text"
    case right           // ">text"
    case absolute(x: Double, y: Double)  // "@x,y text"
}
```

---

## ChordSymbol

```swift
struct ChordSymbol: Hashable {
    let root: PitchClass
    let quality: String      // verbatim (e.g. "m7", "maj7", "dim"); "" = plain major
    let bassNote: PitchClass? // slash-chord (e.g. "C/E" → bassNote=E)
    let raw: String          // verbatim text between quotes
    let source: SourceRange
}
// Written in ABC as "Gm7" directly before the note
```

---

## Tempo

```swift
struct Tempo {
    let prelude: TextString?   // optional text before beats (e.g. "Allegro")
    let beats: [Fraction]      // beat unit(s) — usually [Fraction(1,4)] for Q:=120
    let bpm: Double
    let postlude: TextString?  // optional text after bpm
}
// Q:120 → beats=[Fraction(1,4)], bpm=120.0
// Q:"Adagio" 3/8=60 → prelude="Adagio", beats=[Fraction(3,8)], bpm=60.0
```

---

## TuneMetadata

```swift
struct TuneMetadata {
    let composer: TextString?       // C:
    let origin: [String]            // O: semicolon-split
    let area: TextString?           // A: (deprecated)
    let book: TextString?           // B:
    let discography: TextString?    // D:
    let fileURL: URL?               // F:
    let group: TextString?          // G:
    let history: [TextString]       // H:
    let notes: TextString?          // N:
    let source: TextString?         // S:
    let rhythm: TextString?         // R:
    let transcription: TextString?  // Z:
}
```

---

## Diagnostic / DiagnosticCode

```swift
struct Diagnostic {
    enum Severity { case error, warning, info }
    let severity: Severity
    let code: DiagnosticCode
    let message: String
    let source: SourceRange
    let related: [SourceRange]
    let hint: String?
}

enum DiagnosticCode: String {
    // Music syntax
    case constructOutOfOrder, reservedCharacter, danglingTie
    // Fields
    case unknownField, malformedFieldPayload, missingRequiredField
    // CeolKit extensions
    case invalidPageNumber, misplacedStemAlignment
    // Directives
    case unknownDirective
}
```

---

## CeolKit directives

```swift
enum CeolKitDirective: Hashable {
    case pipeFormat(Bool)    // %%ceolkit:pipeformat true|false
    case pageNumber(Int)     // %%ceolkit:pagenumber N  (N ≥ 1)
    case stemAlignment(Int)  // %%ceolkit:stemalignment N (signed int)
}

struct CeolKitDirectiveScope {
    let directive: CeolKitDirective
    let scope: Scope
    let source: SourceRange
}

enum Scope {
    case fileGlobal           // before first X:
    case tuneGlobal           // in tune header
    case voiceLocal(VoiceId)  // in body after V:
}
```

Validation: `pageNumber` requires N ≥ 1; invalid → `.invalidPageNumber` warning, directive dropped.  
`stemAlignment` in body without preceding `V:` → `.misplacedStemAlignment` warning.  
Last occurrence wins for same directive in same scope.

---

## Dialect

```swift
enum Dialect: Sendable {
    case strict(version: String)  // from %abc-2.1 or I:abc-version
    case loose                     // pre-2.1 or unversioned
}
// Statics: .v2_1, .v2_2
```

Detected from first line `%abc-N.N`; fixed after stage 2 except per-tune override via `I:abc-version`.
In strict mode: reserved characters produce `.error` instead of `.warning`.

---

## SourceRange

```swift
struct SourceRange: Hashable, Identifiable, Sendable, Codable {
    let file: URL?
    let byteOffset: Int
    let length: Int
    let line: Int       // 1-based
    let column: Int     // 1-based
}
```

When parsing from a String (no file), use `file: nil`.

---

## TextString

```swift
struct TextString: Hashable, Codable, Sendable {
    let value: String    // ABC escapes resolved, Unicode
    let source: SourceRange
}
```

---

## Accidental scoping rules (semantic pass)

1. **Key signature** establishes a base alteration for each diatonic step.
2. **Written accidental** in source (`^`, `_`, `=`, `^^`, `__`, microtonal) overrides key for that note and all subsequent notes of the **same step AND same octave** in the **same measure**.
3. **Bar line** resets intra-bar memory; next bar uses key signature again.
4. **`displayedAccidental`** = what the renderer must draw:
   - First occurrence of a non-key-default alteration in the bar → same as `writtenAccidental`
   - Redundant (same as key sig or already established in bar) → `nil`
   - Natural cancelling key sig → the natural sign must display → same as `writtenAccidental`
5. Accidentals do NOT propagate across octaves (^c4 does not affect C3).

---

## Parser recovery contract

The parser **always returns a non-nil `Score`** regardless of input:
- Unrecognised characters → `Token.unknown`, `.reservedCharacter` diagnostic
- Unparseable lines → treated as `freeText`, warning issued
- Malformed field payload → diagnostic `.malformedFieldPayload`, synthetic default applied
- Missing required fields (no `K:`) → `.missingRequiredField`, synthetic `K:C` used
- Malformed bar lines → skip/recover, continue parsing

---

## Conformance test helpers (ConformanceHelpers.swift)

```swift
// extension Measure
var noteEvents: [Note]
var chordEvents: [Chord]
var restEvents: [Rest]
var tupletEvents: [Tuplet]
var graceEvents: [GraceGroup]

// extension Voice
var firstStaff: Staff?
var allMeasures: [Measure]
var firstMeasure: Measure?

// extension Tune
var firstVoice: Voice?
var singleVoiceMeasures: [Measure]   // voices.first?.allMeasures ?? []

// extension Score
var firstTune: Tune?
var errorDiagnostics: [Diagnostic]
var warningDiagnostics: [Diagnostic]

// top-level
func parse(_ source: String, options: ParseOptions = .default) -> ParseResult
```
