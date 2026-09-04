# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CeolKit is a Swift library for parsing [ABC music notation](https://abcnotation.com/wiki/abc:standard:v2.2) (v2.2) into a structured, typed Swift domain model.

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
  CeolKitSVGGeometry/  — reads emitted SVG back into layout geometry (systems,
                        staff size, spans, barlines). Depends on nothing.
  ckprobe/             — development CLI over the parser + renderer + geometry

Tests/
  CeolKitParserTests/
    Conformance/      — all examples from ABC v2.2 §14
    Extensions/
    Recovery/         — malformed inputs that must still produce a Score
  CeolKitSVGGeometryTests/
```

`CeolKitRenderer` defines the protocol(s) all renderers conform to and any layout/metrics helpers shared across backends. Each renderer target is a standalone library product; consumers link only what they need.

### Development tooling

`ckprobe` parses and renders an ABC file and reports what came out — diagnostics, tune
structure, and the geometry of every system on every page. It is the fastest way to answer
a layout question without a GUI:

```bash
swift run ckprobe tune.abc                          # full report
swift run ckprobe tune.abc --scale 0.85             # override %%ceolkit:scale
swift run ckprobe tune.abc --sweep 1.5,1.0,0.85     # systems/pages per scale factor
swift run ckprobe tune.abc --natural                # unstretched system widths
swift run ckprobe tune.abc --out /tmp/out --json
swift run ckprobe tune.abc --out /tmp/out --font-face       # <text> + @font-face
rsvg-convert -w 1500 /tmp/out/page0.svg -o /tmp/page0.png   # to look at a page
```

`ckprobe` renders in whatever mode the library defaults to, which is
`TextRendering.outlines` — glyph geometry in the document, no font environment needed. That
is what makes `rsvg-convert` usable here: like every other non-browser rasteriser it ignores
`@font-face` and resolves `font-family` through fontconfig, so `--font-face` output only
looks right on a machine that happens to have Bravura and Libertinus Serif installed, and
silently substitutes or drops glyphs where it does not.

`CeolKitSVGGeometry` deliberately imports no other CeolKit module: it reads what the
renderer *drew*, so it can be used to check that against what the layout engine believed.

**Do not make `ckprobe` a product.** SwiftPM synthesises the product for executable
targets in the root package, so `swift run` works without one, and leaving it unexported
keeps it out of consumers' dependency graphs. `CeolKitSVGGeometry` *is* a product only
because Tuist (4.202.6) fails to load a graph containing a product-less library target
that anything references — see the comment in `Package.swift`.

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
Six `%%ceolkit:*` directives are first-class model members:
- `%%ceolkit:pipeformat true|false`
- `%%ceolkit:pagenumber N`
- `%%ceolkit:stemalignment N`
- `%%ceolkit:justifylast true|false`
- `%%ceolkit:scale F` (F > 0; tune-wide, never per-voice)
- `%%ceolkit:gracenotespacing F` (F >= 1, in grace notehead widths; tune-wide, never per-voice)

All are represented in `CeolKitDirective` (an enum, not a string map). An unrecognised directive is not represented at all: it produces an `unknownDirective` diagnostic and is dropped. They attach to a `Scope` (`.fileGlobal`, `.tuneGlobal`, `.voiceLocal(VoiceId)`).

### Dialect
```swift
public enum Dialect {
    case strict(version: ABCVersion)  // %abc-2.1 or higher
    case loose                         // pre-2.1 or unversioned
}
```
Dialect is fixed after stage 2 (from the version line / `I:abc-version`), except individual tunes may override it. It controls whether legacy syntax produces warnings vs. errors.

## Release process

Work lands on `develop`; `main` is the release branch and carries the tags. A release is
five steps, and **the last one is not optional**:

1. Verify `develop`: clean tree, `swift build`, `swift test`, CI green on the tip.
2. Open a PR `develop` → `main` titled `Release X.Y.Z`, and merge it with a **merge commit**
   (not squash, not rebase — the tags and the merge-back both depend on the shared history).
3. Tag `main`: `git tag -a vX.Y.Z -m "Release X.Y.Z"` and push the tag.
4. `gh release create vX.Y.Z --title "X.Y[.Z]" --notes-file <notes> --verify-tag`, then
   append the generated PR list (`gh api -X POST repos/sbeitzel/CeolKit/releases/generate-notes
   -f tag_name=vX.Y.Z -f previous_tag_name=<prev>`) above the `## Upgrading` section.
5. **Merge `main` back into `develop` and push.** The release merge commit exists only on
   `main`, so without this `develop` falls behind, and branch protection then refuses the
   *next* release PR as "head branch is not up to date". Skipping it is what makes step 2
   fail later, not now.

Two notes on the mechanics:

- Issues fixed on `develop` stay **open** until step 2 — GitHub only auto-closes
  `Fix #NN` references when they reach the default branch. Do not close them by hand.
- Version numbers live only in the git tag and the GitHub release. Nothing in `Package.swift`
  or the sources needs editing.

## Open Questions (from spec §10)

1. File-global directive bag shape on `Score` — flat array vs. dedicated `FilePreamble` struct
2. Macro expansion timing — eager (simpler) vs. lazy (preserves source intent)
4. Unicode NFC normalisation for `w:` lyric alignment
5. Behavior when `w:` is longer than the note count
