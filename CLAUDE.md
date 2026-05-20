# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CeolKit is a Swift library for parsing [ABC music notation](https://abcnotation.com/wiki/abc:standard:v2.2) (v2.2) into a structured, typed Swift domain model. The spec lives in `ABCParser-Spec.md`. The codebase is pre-implementation; the spec is authoritative.

## Architecture

The parser is a six-stage pipeline:

```
ABC source → Source → Line Classifier → Tokenizer → Syntactic AST → Semantic Pass → Domain Model
```

**Stages 1–4** are purely syntactic (no musical interpretation). **Stage 5** resolves stateful information (key, meter, unit length, voice, macros, accidentals). **Stage 6** is the stable public domain model that consumers depend on.

### Planned module layout (SPM targets)

The package is split so renderers can depend on the domain model without pulling in the parser.

```
Sources/
  CeolKitModel/        — §6 domain types (Score, Tune, Voice, Measure, Event, …)
                        All types are Sendable + Codable. No parser dependency.
  CeolKitParser/       — stages 1–5; depends on CeolKitModel
    Source/           — SourceRange.swift
    Lexer/
    LineClassifier.swift
    Tokens/
    AST/
    Fields/           — one file per information field type (K:, M:, Q:, etc.)
    Semantic/         — state manager, accidental scoping, voice resolution
    Diagnostics/
    Extensions/       — %%ceolkit:* directive parsing and scoping
  CeolKitRenderer/     — renderer protocol + shared rendering utilities
                        depends on CeolKitModel only

Tests/
  CeolKitParserTests/
    Conformance/      — all examples from ABC v2.2 §14
    Extensions/
    Recovery/         — malformed inputs that must still produce a Score
```

`CeolKitRenderer` defines the protocol(s) all renderers conform to and any layout/metrics helpers shared across backends. Each renderer target is a standalone library product; consumers link only what they need.

## Key Design Decisions

### Two-layer output
- **Syntactic AST** (`ABCFile`, `ABCTune`, `MusicElement`, `NoteToken`): mirrors source syntax 1:1, no information lost or resolved. Available to consumers wanting custom interpretation.
- **Domain model** (`Score`, `Tune`, `Voice`, `Measure`, `Event`): fully resolved, self-contained musical events. The stable public API surface.

### Recovery contract
The parser **always returns a `Score`**, even on error. Every stage has a recovery path:
- Lexer: `Token.unknown` for unrecognised characters
- Line classifier: unparseable lines become `LogicalLine.freeText` with a warning
- Field parser: malformed payloads become `InformationField.unknown`
- Semantic pass: missing required fields (e.g. no `K:`) produce an error but still yield a `Tune` with a synthetic default

### Accidentals
`AccidentalToken` (syntactic, from source) is distinct from `Alteration` (semantic, normalised rational). `Alteration` stores microtonal accidentals as `numerator/denominator` (`Int`/`Int`, always reduced, `denominator > 0`) — never floating point.

```swift
// quarter-sharp = Alteration(numerator: 1, denominator: 2)
// three-quarter-flat = Alteration(numerator: -3, denominator: 2)
```

### Note representation split
`Note` carries both `writtenAccidental` (what was in the ABC source) and `displayedAccidental` (what a renderer should draw after key signature and intra-bar accidental memory). These differ, e.g., for the second `c` after `^c` in C major.

### CeolKit extensions
Three `%%ceolkit:*` directives are first-class model members:
- `%%ceolkit:pipeformat true|false`
- `%%ceolkit:pagenumber N`
- `%%ceolkit:stemalignment N`

All are represented in `CeolKitDirective` (an enum, not a string map) with an `.unknown(name:payload:)` case for forward compatibility. They attach to a `Scope` (`.fileGlobal`, `.tuneGlobal`, `.voiceLocal(VoiceId)`).

### Dialect
```swift
public enum Dialect {
    case strict(version: ABCVersion)  // %abc-2.1 or higher
    case loose                         // pre-2.1 or unversioned
}
```
Dialect is fixed after stage 2 (from the version line / `I:abc-version`), except individual tunes may override it. It controls whether legacy syntax produces warnings vs. errors.

## Open Questions (from spec §10)

1. File-global directive bag shape on `Score` — flat array vs. dedicated `FilePreamble` struct
2. Macro expansion timing — eager (simpler) vs. lazy (preserves source intent)
3. Passthrough for `%%MIDI` directives from abcm2ps/abc2midi
4. Unicode NFC normalisation for `w:` lyric alignment
5. Behavior when `w:` is longer than the note count

## v0.1 Scope

Implement through: file structure, all v2.2 information fields, line continuation, music parser (pitches/octaves/accidentals including microtonal/lengths/broken rhythm/rests/bar lines/repeats/ties/slurs/chords/decorations/chord symbols/annotations), semantic pass (K/L/M/V/U resolution, accidental scoping, ties across bars, single- and multi-voice), all three `%%ceolkit:*` extensions, strict+recoverable diagnostics, conformance test suite.

Deferred to v0.2+: grace note timing, complex `P:` parts, macros, voice overlay (`&`), custom transposition, symbol lines (`s:`).
