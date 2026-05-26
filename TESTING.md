# Renderer Test Plan

A breakdown of the test categories the SVG renderer (and any future renderer) should cover.
All are strong candidates for snapshot tests: SVG output is deterministic given the same `Score`,
so reference SVG files serve as golden files that catch layout regressions without manual inspection.

## Testing Library: SnapshotTesting (under consideration)

We plan to use Point-Free's [`swift-snapshot-testing`](https://github.com/pointfreeco/swift-snapshot-testing)
for the SVG renderer tests. It has not yet been added as a package dependency — several open questions
need to be resolved first:

**Bootstrap: how do we record initial snapshots?**
SnapshotTesting records a reference file on the first run (when none exists), then asserts on every
subsequent run. That means the renderer must be substantially implemented before any snapshot can be
recorded — there is nothing to record against a stub that always throws. Options:
- Record snapshots only after the renderer reaches a "good enough" milestone, and treat the recording
  run as a deliberate manual step (e.g., `swift test --filter RendererTests -- record`).
- Write the tests now but gate them with `#if RECORD_SNAPSHOTS` or skip them until the renderer
  is ready, to avoid spurious failures on CI in the interim.

**Should snapshots be committed to the repo?**
Arguments for committing them:
- CI can run the assertion pass without a prior recording step.
- Diffs in PRs make layout regressions visible in code review.
Arguments against:
- SVG reference files can be large and numerous; they bloat `git log` and slow clones.
- Any intentional renderer change requires a mass re-record and a noisy commit.
Likely answer: commit them, but keep them in a dedicated `Tests/__Snapshots__/` subtree so they are
easy to exclude from blame and diff views. Re-evaluate if size becomes a problem.

**Cleaning / re-recording snapshots**
When a renderer change is intentional, all affected snapshots need to be re-recorded. Considerations:
- A `scripts/reset-snapshots.sh` that deletes the `__Snapshots__` directory and re-runs the suite in
  record mode would make this a one-command operation.
- SnapshotTesting supports a `record` parameter per test and a global `isRecording` flag; a
  `RECORD_SNAPSHOTS=1` environment variable passed to `swift test` could set the flag without
  modifying test source.
- CI should never run in record mode; record mode should require an explicit local opt-in.

**Transitive dependencies**
`swift-snapshot-testing` brings in two dependencies:
- `swift-custom-dump` (Point-Free) — used for pretty-printing diffs in failure output.
- `swift-syntax` (the Swift project) — required by `InlineSnapshotTesting`; pulled in even if only
  `SnapshotTesting` is used. This adds non-trivial compile time and should be weighed accordingly.

## Structural / Layout

- Empty staff — five lines, correct proportions, no content
- Clef rendering — treble, bass, alto, tenor, percussion (K:perc), and the HP bagpipe pseudo-clef
- Measure with a single whole rest
- Line breaking — long tunes wrap correctly; `%%ceolkit:pipeformat` changes the wrapping strategy
- Multi-system layout — more than one row of staves
- Page number injection — `%%ceolkit:pagenumber N` appears in the right place
- Multi-tune score — two or more tunes separated correctly on the page

## Key Signatures

- C major / K:none (no accidentals drawn)
- All seven sharp keys (G through C#)
- All seven flat keys (F through Cb)
- Modal keys (Dorian, Phrygian, etc.) — same accidentals as relative major
- K:HP / K:Hp (no conventional sig, Highland Pipe)
- Key with explicit modifications (`K:D Phr ^f`)
- Mid-tune key change (cancellation naturals + new sig)

## Meter / Time Signatures

- Common time (4/4 and the **C** glyph)
- Cut time (2/2 and the **₵** glyph)
- Simple meters: 3/4, 2/4, 6/8
- Compound/odd: 9/8, 12/8, 5/4, 7/8
- No meter (`M:none`)

## Notes & Durations

- Each note head position: ledger lines above and below, all five staff lines/spaces
- Duration glyphs: whole, half, quarter, 8th, 16th, 32nd
- Dotted and double-dotted notes
- Stems up vs. stems down, including the crossover rule at the midline
- Beam groups (two 8ths, four 16ths, broken-rhythm pairs)
- `%%ceolkit:stemalignment` overrides

## Accidentals

- Sharp, flat, natural in isolation
- Double-sharp, double-flat
- Microtonal (quarter-sharp, three-quarter-flat, etc. — stored as `Alteration(numerator:denominator:)`)
- Courtesy/reminder accidentals: `displayedAccidental` vs. `writtenAccidental` diverge (e.g., second `^c` in a bar)

## Rests

- Whole, half, quarter, eighth, sixteenth rest glyphs
- Full-measure rest (whole rest centered, regardless of meter)
- Multi-measure rest number (e.g., `Z4`)

## Chords & Tuplets

- Two-note and three-note vertical chords, correct stem direction
- Triplet bracket + "3"
- Other tuplets (5:4, 7:4, etc.) with bracket and ratio label

## Bar Lines

- Single bar line
- Double bar line
- Final bar line (thin + thick)
- Repeat start (`|:`) and repeat end (`:|`)
- Start-end repeat (`::` / `:|:`)
- First and second endings (volta brackets)

## Text / Metadata

- Title (`T:`) — centered, large
- Composer (`C:`) — right-aligned
- Rhythm/genre (`R:`)
- Origin (`O:`) and source (`S:`)
- Transcription (`Z:`)
- Notes (`N:`) as footnote-style text
- Tempo marking (`Q:`) — beat note + number, or text string
- Lyrics (`w:`) — syllables under their notes, hyphen/underscore continuation

## Decorations

- Dynamics: ppp, pp, p, mp, mf, f, ff, fff, sfz
- Articulations: staccato dot, tenuto, accent (`>`), strong accent
- Ornaments: trill (with start/end span), mordent, pralltriller, roll, turn, inverted turn
- Fermata above and inverted fermata below
- Bowing: upbow, downbow
- Fingering numbers (0–5)
- Hairpins: crescendo and decrescendo spanning multiple events
- Navigation: segno, coda, D.C., D.C. al Fine, D.S. al Coda, etc.
- Breath mark and caesura

## Ties & Slurs

- Tie between two adjacent notes (same pitch)
- Tie crossing a bar line
- Slur over a group of notes
- Slur crossing a bar line

## Multi-Voice

- Two voices on one staff (voice 1 stems up, voice 2 stems down)
- `%%ceolkit:stemalignment` per-voice effect

## Annotations & Chord Symbols

- Guitar chord symbol above a note (`"Dm"`)
- Free annotation with placement (above `^`, below `_`, left `<`, right `>`, centered `@`)
