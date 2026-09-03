# Extensions

This file documents formatting behaviour that is implemented in this project but is
not dictated by the ABC v2.2 [standard](https://abcnotation.com/wiki/abc:standard:v2.2):
the `%%ceolkit:*` directives, which the standard does not define at all, and the choices
CeolKit makes where the standard asks for an outcome but names no rule for reaching it.

---

## `%%ceolkit:gracenotespacing`

**Syntax:** `%%ceolkit:gracenotespacing <number ≥ 1>`

**Type:** floating-point number, at least `1`

**Default:** `1.05`

**Scope:** global (file preamble or tune header); tune-wide, never per-voice

### Description

Sets the step between adjacent grace noteheads inside a single grace group, as a
multiple of the grace notehead width. `1.0` puts each notehead exactly one
notehead width after the one before it — noteheads touching, the tightest
setting that does not overlap. The default `1.05` leaves a hairline between
them, which is how a beamed embellishment is normally engraved.

This is a page-fit knob. Dense settings — piobaireachd, heavily embellished
strathspeys — can go tighter to hold a part on one page; sparse or teaching
settings, and large print, can open the groups up.

The factor governs only the step *between* noteheads within one group. It does
not change the padding at the outer edges of a group, nor the gap between the
group and the note it decorates.

Because a note carrying an accidental needs room for the accidental glyph to
the left of its head, the step into that note is whatever the accidental
requires when that is more than this factor allows.

A value below `1` would overlap adjacent noteheads. It produces a warning and
the directive is ignored, leaving the tune at the renderer's default — as do a
missing and a non-numeric argument.

Per-voice spacing is not supported: a value set in a tune body applies to the
whole tune regardless of which voice is current. Grace groups in different
voices of one system are spaced alike.

### Single grace notes are unaffected

A one-note grace group is one notehead wide whatever the factor is, because
there is no second notehead to step to. The space before the principal note is
governed instead by the overhang of the 32nd-note flag on the grace stem. If
the complaint is about the room around a *single* grace note, this directive is
not the lever.

### Interaction with `%%ceolkit:scale`

The two are independent and do not compound. `%%ceolkit:scale` sets the staff
size, and the grace notehead is measured from it; `%%ceolkit:gracenotespacing`
is a ratio applied within the group. Halving the scale halves the drawn width of
a grace group, because the noteheads themselves are half the size — the number
of notehead widths between them is unchanged.

### Scoping

Like the other CeolKit directives, the value is set where it is encountered and
persists until changed. A value in the file preamble governs every tune in the
file, and a tune header can override it for that tune and the ones that follow.

### Examples

#### Tighten the embellishments to hold a part on one page

```abc
X:1
T:A Densely Embellished Strathspey
M:4/4
L:1/8
%%ceolkit:gracenotespacing 1.0
K:A
{gcd}A2 {gcdge}A2 {gag}B2 {gcd}c2|
```

#### Open them up for teaching copy

```abc
%%ceolkit:gracenotespacing 1.6
X:1
T:Learner's Copy
M:4/4
L:1/8
K:A
{gcd}A2 {gcdge}A2|
```

---

## `%%ceolkit:justifylast`

**Syntax:** `%%ceolkit:justifylast <true|false>`

**Type:** boolean (`true` or `false`; case-insensitive)

**Default:** `false`

**Scope:** global (file preamble or tune header)

### Description

The default way to render a tune is not to justify the last line, leaving it ragged.
This setting, when `true`, forces the last line to be justified so that it spans the
whole width.

---

## `%%ceolkit:pipeformat`

**Syntax:** `%%ceolkit:pipeformat <true|false>`

**Type:** boolean (`true` or `false`; case-insensitive)

**Default:** `false`

**Scope:** global (file preamble); last occurrence wins

> **Note:** This directive follows the
> [ABC application-specific directive convention](https://abcnotation.com/wiki/abc:standard:v2.2#application_specific_directives)
> (`%%app:directive`).

### Description

Enables Highland bagpipe formatting for the entire conversion.
When `%%ceolkit:pipeformat true` is present, note stems, key signatures, and
other typesetting decisions are adjusted for bagpipe notation (GHB tuning,
no key-signature accidentals, etc.).

### Examples

#### Enable bagpipe mode in-file

```abc
%%ceolkit:pipeformat true
X:1
T:Hana's Wedding
M:4/4
L:1/8
K:HP
...
```

#### Explicitly disable (no-op — same as omitting the directive)

```abc
%%ceolkit:pipeformat false
X:1
T:My Tune
M:4/4
L:1/8
K:G
GABG|DEFD|GABG|D4|
```

#### Last occurrence wins

```abc
%%ceolkit:pipeformat true
%%ceolkit:pipeformat false   %% this is the last one, so bagpipe mode is OFF
X:1
...
```

---

## `%%ceolkit:pagenumber`

**Syntax:** `%%ceolkit:pagenumber <positive integer>`

**Type:** integer

**Default:** `1` (first page is page 1)

**Scope:** global (file preamble or tune header)

### Description

Sets the current page number to the given positive integer. Subsequent pages
are numbered sequentially from that value. This allows a document to start
numbering from a page other than 1, which is useful when a piece of music
spans multiple separately-rendered files.

The value must be a positive integer (≥ 1). If the argument is missing, zero,
negative, or non-numeric, an error message is emitted and the directive is
ignored.

Page number substitution in the footer uses the `$P` placeholder, which is the token
this directive sets. It is one of four — see
[`%%footer` placeholders](#footer-placeholders).

This directive fixes the number **at authoring time**, which is what a multi-file
*score* needs — the file that continues a piece knows where the previous file
stopped. It cannot help a multi-file *compilation*: a tune assembled into a binder
alongside others sits at a different offset in every binder it appears in, and the
offsets shift whenever any of the tunes before it gains or loses a page. For that,
mark the span and let the tool building the binder fill it in — see
[Consumer-substitutable footer spans](#consumer-substitutable-footer-spans).

### Examples

#### Start numbering from page 3

```abc
%%ceolkit:pagenumber 3
%%footer "Page $P"
X:1
T:My Tune
M:4/4
L:1/8
K:G
GABG|DEFD|GABG|D4|
```

The footer on the first (and only) page reads "Page 3".

#### Multi-file score continuation

When a score is split across two separate ABC files, the second file can
continue page numbering from where the first left off:

```abc
%% --- second file ---
%%ceolkit:pagenumber 5
%%footer "$P"
X:2
T:Continued
...
```

### Where it is read

The last statement of the directive wins, and only the **file preamble and the first
tune's header** are read. The number is set *before any output has been produced*, so
that is the only place it can mean anything; a copy in a later tune's header would be
asking to renumber pages already engraved, and is ignored.

The number reaches both the `$P` and `${pagenumber}` substitutions in the footer and
the `page` field of the `ceolkit-meta` scroll-sync comment, so a consumer pairing a
rendered page with what the reader sees on paper agrees with the printed footer.

### Interaction with `%%newpage`

> **Not yet implemented.** `%%newpage` is not supported — it reports
> `info: Unsupported stylesheet directive '%%newpage'` and no page break occurs. It is
> requested as [#140](https://github.com/sbeitzel/CeolKit/issues/140); this section
> describes what the two directives will mean together once it lands.

`%%newpage N` also sets the page number as a side-effect of forcing a page
break. `%%ceolkit:pagenumber N` sets the page number *without* starting a new page,
so it is only meaningful before any output has been produced (i.e., in the
file preamble or at the very start of a tune header).

---

## `%%footer` placeholders

**Syntax:** `$<letter>` inside a `%%footer` template

**Scope:** the footer template it is written in

### Description

CeolKit substitutes exactly four `$` placeholders:

| Placeholder | Value |
|-------------|-------|
| `$P` | the current page number, as set by [`%%ceolkit:pagenumber`](#ceolkitpagenumber) |
| `$T` | the first tune's title |
| `$D` | the render date, formatted by `%%dateformat` |
| `$d` | the same as `$D` |

That set is deliberately narrower than abcm2ps's, which also defines `$F`, `$I<x>`,
`$V`, `$P0` and `$P1`. None of those are implemented here, and neither is anything
outside the table above.

### Anything else is engraved literally, and diagnosed

A `$` followed by any other letter is not a placeholder. It stays in the literal text
and is engraved as written — under the default `TextRendering.outlines` as artwork, with
nothing downstream able to tell what was meant — so the parser emits a warning for each
distinct one:

```
warning: '$X' is not a footer placeholder; it will be engraved literally
```

That covers both an abcm2ps placeholder CeolKit does not implement and a typo such as
`$p`. Two things are *not* diagnosed, because neither is a token: a `$` not followed by
a letter (`$5`, a trailing `$`) is ordinary text, and `${name}` is a
[consumer-substitutable span](#consumer-substitutable-footer-spans).

---

## Consumer-substitutable footer spans

**Syntax:** `${<name>}` inside a `%%footer` template

**Scope:** the footer template it is written in

### Description

`${name}` marks a span of the footer as *substitutable*: CeolKit still lays out and
draws its own value there, but the renderer emits that span as one findable,
self-describing SVG element instead of as loose text or loose glyphs, so a downstream
tool can replace it.

This exists because outlining is a one-way door. Under the default
`TextRendering.outlines` a footer reading `Page 1` leaves the renderer as six `<use>`
elements and no text anywhere in the document — there is nothing left for a
post-processor to rewrite, and only CeolKit still has the font, the metrics and the
layout needed to draw a different string in that spot. The mark is how an author says
in the ABC source that a particular span is somebody else's to fill in.

The motivating case is a binder: a server renders each tune's `.abc` on its own and
concatenates the pages, so page 1 of the third tune has to print `17`. No value of
[`%%ceolkit:pagenumber`](#ceolkitpagenumber) is right for that, because the offset is
not knowable when the ABC is written.

`${…}` is a CeolKit extension. It is not part of the ABC v2.2 header/footer
substitution set, and it is understood only in `%%footer`.

### What is emitted

Each marked span becomes a group wrapping CeolKit's own rendering of the default value:

```xml
<g id="ceolkit-tag-pagenumber" class="ceolkit-tag" data-ceolkit-tag="pagenumber"
   data-x="306" data-y="753.048" data-font-size="12"
   data-font-family="Libertinus Serif" data-text-anchor="middle">
  <!-- CeolKit's own rendering of the default value: outlined or <text>, per mode -->
</g>
```

The `data-*` attributes are the contract; the group's contents are CeolKit's. A
consumer substitutes by emptying the group and drawing its own text at the advertised
anchor — position, size and anchor are what a stamping API needs, not the face.

Three properties follow, and all three are deliberate:

- **It carries its own default.** A standalone render is unchanged and correct, and a
  consumer that ignores the group gets exactly the output it always got.
- **It is mode-independent.** `.outlines`, `.fontFace` and `.both` all wrap the same
  way, so a consumer never has to care which mode produced the file — and `.outlines`
  stays the default, with no hole in the guarantee it exists to give.
- **`id` is unique, `data-ceolkit-tag` is not.** Nothing stops a template from marking
  one name twice; the first gets `ceolkit-tag-<name>` and later ones are suffixed
  `-2`, `-3`, … . `data-ceolkit-tag` carries the name unchanged on every one, so a
  consumer keying off that finds them all.

### Names

A name is a letter followed by letters, digits, `_`, `.` or `-`. Anything else —
`${1st}`, an unclosed `${`, a bare `${}` — is not a mark and is engraved literally,
which is what an author who did not mean a mark expects to see.

Four names carry a value CeolKit knows:

| Name | Default value |
|------|---------------|
| `${pagenumber}` | the current page number — the same value as `$P` |
| `${pagecount}` | the number of pages in this render |
| `${title}` | the first tune's title — the same value as `$T` |
| `${date}` | the render date, formatted by `%%dateformat` — the same value as `$D` |

Any other name is a mark CeolKit has no value for. It draws nothing and emits an
empty group at the right spot, which is exactly what a consumer that means to stamp
its own text there wants: a binder name or a section title is not CeolKit's to invent.

### Layout and overflow

A substituted string is usually a different width from the default (`9` becomes
`117`). CeolKit reserves the width of its own default and advertises the anchor;
the consumer owns the overflow. Two rules make that workable:

- A column that is **nothing but the mark** keeps that column's own anchor, so a wider
  replacement grows the way the column does — leftwards from the right margin,
  outwards from the centre — and stays on the page.
- A mark **mixed with other text** is placed after the text it follows, at
  `text-anchor="start"`. A longer replacement then overflows to the right of the mark,
  over whatever follows it in that column.

So for a page number that a consumer will rewrite, give it a column of its own.

### Examples

#### A page number a binder compiler fills in

```abc
%%footer "$T\t\t${pagenumber}"
X:1
T:My Tune
M:4/4
L:1/8
K:G
GABG|DEFD|GABG|D4|
```

The rendered page reads `My Tune` at the left margin and `1` at the right. The `1`
sits inside `<g id="ceolkit-tag-pagenumber" … data-text-anchor="end">`, so a binder
compiler replaces it with `17` — right-aligned at the same margin — without knowing
anything about the font.

#### A name CeolKit has no value for

```abc
%%footer "${bindername}\t$T\t${pagenumber}"
```

The centre column engraves the tune title as usual. The left column is an empty group
at the left margin waiting for the compiler's binder name, and the right column is the
page number as above.

---

## `%%ceolkit:scale`

**Syntax:** `%%ceolkit:scale <positive number>`

**Type:** floating-point number, greater than zero

**Default:** `1.0` (the renderer's own staff size, unmodified)

**Scope:** global (file preamble or tune header); tune-wide, never per-voice

### Description

Scales the rendered music relative to the renderer's default size, so
`%%ceolkit:scale 0.8` engraves everything at 80%. This is the in-source
counterpart to the SVG renderer's `staffSize` configuration value, and it is
the way to fit a long tune onto one page or to match the size of an adjacent
engraving without changing the caller's render configuration.

The factor multiplies the staff size, and with it every dimension derived from
it: note heads, stems, beams, accidentals, clefs, and the vertical gaps between
systems and between tunes.

Page size and margins are **not** scaled — they stay in absolute points, so
scaling the music never resizes the page. Because the usable width is
unchanged, a smaller factor fits more measures onto each staff line. Title,
subtitle, and composer rows are also unscaled; they are typeset in absolute
point sizes.

The value must be greater than zero. A missing, zero, negative, or non-numeric
argument produces a warning and the directive is ignored, leaving the tune at
the renderer's default size.

Per-voice scaling is not supported: a scale set in a tune body applies to the
whole tune regardless of which voice is current.

### Scoping

Like the other CeolKit directives, the value is set where it is encountered and
persists until changed. A factor in the file preamble therefore governs every
tune in the file, and a tune header can override it for that tune and the ones
that follow.

### Examples

#### Fit a long tune onto one page

```abc
X:1
T:A Long Reel
M:4/4
L:1/8
%%ceolkit:scale 0.75
K:D
|:DEFD ADFD|DEFD AFEC|DEFD ADFD|1 EFED CDEC:|2 EFED CEAc||
```

#### File-wide default with a per-tune override

```abc
%%ceolkit:scale 0.8
X:1
T:Rendered at 80%
M:4/4
L:1/8
K:G
GABG|DEFD|

X:2
T:Rendered at 60%
M:4/4
L:1/8
%%ceolkit:scale 0.6
K:G
GABG|DEFD|
```

The first tune (and any tune that follows without its own directive) renders at
80%; the second, and every tune after it, renders at 60%.

### Relationship to `%%scale`

`abcm2ps` spells this `%%scale`. CeolKit uses the `%%ceolkit:` namespace instead,
both for consistency with the rest of these extensions and to avoid implying
full `%%scale` compatibility. A bare `%%scale` is still reported as an
unsupported stylesheet directive.

---

## `%%ceolkit:stemalignment`

**Syntax:** `%%ceolkit:stemalignment <integer>`

**Type:** integer

**Default:** `0` (disabled)

**Scope:** global (tune header or file preamble), or voice-level (tune body)

### Description

Forces all note stems to end at a fixed vertical position relative to the
centre line of the staff, rather than at the default length computed from the
note head position. The integer argument encodes both the direction of the
stems and the target endpoint:

- A **negative** value forces stems **downward**; the target endpoint is
  `|value|` diatonic steps *below* the staff centre.
- A **positive** value forces stems **upward**; the target endpoint is
  `|value|` diatonic steps *above* the staff centre.
- `0` disables the directive (default behaviour).

### Staff centre reference

The staff centre is the middle line of a standard five-line staff. For common
clefs, the note on the centre line is:

| Clef   | Centre-line note |
|--------|-----------------|
| Treble | B4              |
| Alto   | C4 (middle C)   |
| Tenor  | A3              |
| Bass   | D3              |

### Examples

#### Global: stems down to middle C (treble clef)

Middle C (C4) is 6 diatonic steps below the treble-clef centre line (B4).

```abc
X:1
T:Stems aligned at middle C
M:4/4
L:1/4
%%ceolkit:stemalignment -6
K:C treble
GABC | DEFG | ABCD | EFGc |
```

All stems are forced downward. The stem tips align at the C4 ledger line
below the staff.

#### Global: stems up, six steps above centre

```abc
X:2
T:Stems aligned at A5
M:4/4
L:1/4
%%ceolkit:stemalignment 6
K:C treble
CDEF | GABc | cBAG | FEDC |
```

All stems are forced upward. The stem tips align at A5, six diatonic steps
above B4.

#### Voice-level override

When `%%ceolkit:stemalignment` appears inside the tune body (after a `V:` switch), it
overrides the global value for that voice only. The directive must be placed
on its own line, immediately after the `V:<name>` line.

```abc
X:3
T:Per-voice stem alignment
M:4/4
L:1/4
K:C treble
V:1
%%ceolkit:stemalignment -4
GABc | cBAG |
V:2
%%ceolkit:stemalignment 4
GABc | cBAG |
```

Voice 1 uses `%%ceolkit:stemalignment -4` (stems down to E4, the bottom staff line);
voice 2 uses `%%ceolkit:stemalignment 4` (stems up to F5, the top staff line). Setting
a voice-level value does not change the global `%%ceolkit:stemalignment`; other voices
continue to use the global value (or their own voice-level override, if any).

#### Beamed groups

`%%ceolkit:stemalignment` applies to beamed notes as well as individual notes. Because
all stem tips in a beamed group are set to the same fixed position, the beam
will be rendered horizontally.

```abc
X:4
T:Beamed notes with stemalignment
M:4/4
L:1/8
%%ceolkit:stemalignment -6
K:C treble
cdef gabc' | c'bag fedc |
```

### Behaviour when the note head reaches or crosses the target

If a note head is already at or below (for stem-down) or at or above (for
stem-up) the alignment target, the stem is drawn with a minimum length of one
diatonic step beyond the note head. This prevents zero-length or
inverted stems while still indicating that the alignment constraint could not
be satisfied for that note.

```abc
X:5
T:Notes crossing the alignment target
M:2/4
L:1/8
%%ceolkit:stemalignment -6
K:C treble
cBAG | FEDC | B,2 z2 |
```

Notes from c5 down to D4 align at C4. At C4 itself the stem is drawn with
the minimum stub. B3 (below the target) also receives a minimum stub.

### Interaction with other directives

- **`%%stemdir` / `V: up` / `V: down`**: `%%ceolkit:stemalignment` overrides the stem
  *length* calculation but operates after the stem *direction* has been set.
  When used alongside explicit direction overrides, the alignment target is
  applied in the forced direction.
- **Stemless notes** (`!stemless!` decoration or `%%stemless`): Stemless notes
  are unaffected; `%%ceolkit:stemalignment` is ignored for them.
- **Grace notes**: Grace-note stems are not affected by `%%ceolkit:stemalignment`.

### Resetting

To revert to default stem-length behaviour within a tune, set the value back
to zero:

```abc
%%ceolkit:stemalignment 0
```

A voice-level reset of `%%ceolkit:stemalignment 0` restores that voice to the global
setting.

---

## Floating voices — how the staff is chosen

**Applies to:** a voice marked `*` in `%%score` / `%%staves` (ABC v2.2 §11.1)

### What the standard says, and does not say

§11.1:

> If a single voice surrounded by two voice groups is preceded by a star (`*`), the voice is
> marked to be floating. This means that the voice won't be printed on its own staff; rather
> the software should automatically determine, for each note of the voice, whether it should
> be printed on the preceding staff or on the following staff.

It names the outcome and no rule for reaching it, and it permits software to give up and
print the whole voice on the preceding staff. CeolKit does the real thing, by the rule
below. The rule is ours; a different program will make different choices, and both are
conforming.

### The rule

**A split pitch.** Everything at or above the split goes to the staff above, everything
below it to the staff below.

- Where the voice states `V: … middle=`, that pitch **is** the split.
- Otherwise the split is the diatonic midpoint between the bottom line of the staff above
  and the top line of the staff below, each read through its own clef. For the
  treble-over-bass grand staff the directive was invented for, that is middle C.

An octave-shifted clef (`clef=treble+8`) does not move the split: the shift changes what the
staff sounds, not where its notes are written, and this is a question about where the ink
goes.

**The atom, not the note, is what is assigned.** A beam group, a tuplet, a chord and a tie
chain each go somewhere whole — a beam drawn half on one staff and half on the other is not
merely ugly, it is undrawable. Within an atom the majority of the noteheads decides, and a
tie is broken toward the atom's first note. A grace group goes wherever the note it
ornaments goes, and contributes no vote of its own. A rest goes where the music around it
went.

**Hysteresis, so a melody on the split does not flicker.** An atom whose mean pitch lies
within **one diatonic step** of the split stays on the staff the previous atom went to.
Without it, a phrase sitting on the split changes staff every time it crosses by a step,
which is unreadable however defensible each individual choice was. The first atom of a
voice has nothing to hold it, so its pitch decides.

**Only one neighbour.** A floating voice written at the top or the bottom of a plan — or one
whose neighbour on one side prints nothing — has no choice left to make. It is printed on
the staff it does have, throughout, and a `staffPlanNotFullyApplied` warning says so. The
music is never dropped.

### What this looks like on the page

Each half of a floating voice joins its host staff as an ordinary extra voice, so everything
a `( … )` shared staff already does applies to it: the two are merged onto a common onset
grid, their stems are opposed, and unisons between them are pulled apart. The half stems
away from the staff its music came from — down on the staff above, up on the staff below —
unless the voice stated its own `V: … stem=`, which is always obeyed.

The host staff's clef, key and name stay those of the voice written at the top of it. A
floating voice is at the top of neither staff and never supplies them.

A slur that opens on one staff and closes on the other is drawn as two dangling arcs, one to
each system edge, the way any slur left open across a break is drawn.

### Example

```abc
X:1
T:Floating voice
M:4/4
L:1/8
%%score {RH *M| LH}
V:RH clef=treble
V:M
V:LH clef=bass
K:C
V:RH
c2e2g2e2|
V:M
G2A2B2c2|
V:LH
C,4G,,4|
```

`M`'s notes sit above middle C, so they are drawn on the right hand's staff. Written an
octave lower they would be drawn on the left hand's. To move the boundary without moving the
music, give the voice a middle note of its own:

```abc
V:M middle=e
```

which puts the split at E5 and sends the same four notes downstairs.

---

## Voice overlay — where an `&` winds back to

**Applies to:** the `&` operator in the tune body (ABC v2.2 §7.4)

### What the standard says, and does not say

§7.4:

> The `&` operator may be used to temporarily overlay several voices within one measure. Each
> `&` operator sets the time point of the music back by one bar line, and the notes which
> follow it form a temporary voice in parallel with the preceding one. This may only be used
> to add one complete bar's worth of music for each `&`.

Two of its terms have to be pinned down before an implementation can exist, and the standard
pins neither. CeolKit reads them as follows; the readings are ours, and they are what its own
two examples need in order to work.

### The rule

**"Back by one bar line" means back to the last bar line crossed.** Where music has already
been written in the bar now open, that is the head of *this* bar. Where none has — an `&` at
the head of a line, or straight after a bar line — it is the head of the bar *before*. A run
of `&`s winds back one further bar for each, so `&&` written at the head of a line overlays
the two bars of the line above it, which is what the standard's own second example asks for.

**An `&` layer lives for the rest of its source line.** A bar line does not close it: `&& (d8
| c6) c2|` is one temporary voice across two bars, again per the second example. What ends it
is the end of the line, and the first `&` of the next line reopens *the same* temporary
voice — one `&` on each of two lines is two bars of one part, not two parts of one bar each.

**A line that opens with `&` is a continuation of the line above.** It shares that line's
stave — the overlay is printed on the same system as the music it overlays, not on the next
one — and it leaves the lyric anchor alone, so a `w:` after it still matches the notes above.
That is §7.4's own "disregarding any overlay in the accompanying music code", which CeolKit
applies to `s:` lines equally.

**A bar line closes the bar for every layer standing in it.** The bar line belongs to the
staff, not to whichever layer was current when it was typed.

**An overlay is a voice.** Its accidentals are scoped to its own bar (§4.2 scopes them to the
voice that wrote them), its notes beam among themselves, and its ties and slurs pair only
with its own. It is written in the key and against the unit note length of the voice it
overlays, because it *is* that voice's music.

### Recovery

An overlay that supplies more bars than its `&`s wound back over breaks the standard's "one
complete bar's worth of music for each `&`". CeolKit warns (`voiceOverlayTooLong`) and prints
the extra bars anyway, giving the voice beneath them the empty bars it now needs: dropping
music the author wrote to enforce a counting rule would be the worse failure.

An `&` written where there is no bar to wind back to — at the very start of a voice — warns
(`voiceOverlayWithoutBar`) and starts the overlay at the first bar.

### What this looks like on the page

Each layer joins its voice's staff as an ordinary extra voice, directly beneath it, so
everything a `( … )` shared staff already does applies to it: the layers are merged onto a
common onset grid, the outer two have their stems opposed, simultaneous rests are moved off
centre, and unisons between them are pulled apart. A tune written with `&` and the same tune
written as a `%%score ( … )` group of the same parts draw the same noteheads in the same
places.

The staff's clef, key and name stay those of the voice itself. An overlay never supplies
them, and no `%%score` can name, place or leave one out: it belongs to its voice and goes
wherever the plan sends that voice.

### Example

```abc
X:1
T:Voice overlay
M:6/8
L:1/8
K:C
A2 | cdefga &\
     AAAAAA &\
     FEDCB,A, |]
```

Three parts on one staff for the second bar, and one for the first. Written on separate
lines instead, with the `&`s leading, it means the same thing:

```abc
X:1
T:Voice overlay
M:6/8
L:1/8
K:C
A2 | cdefga |]
   & AAAAAA |]
   & FEDCB,A, |]
```
