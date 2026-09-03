# Conformance notes

How CeolKit reads the parts of the [ABC 2.2 standard](https://abcnotation.com/wiki/abc:standard:v2.2)
where the standard leaves a choice to the software, and where CeolKit's answer differs from
the one `abcm2ps` gives.

Non-standard `%%ceolkit:*` directives are documented separately, in
[EXTENSIONS.md](EXTENSIONS.md).

---

## §11.1 Voice grouping — `%%score` and `%%staves`

`V:` says which voice a line of music belongs to. It does not say what staff that voice is
drawn on, or what furniture stands to the left of it. `%%score` does.

```abc
%%score Solo  [(S A) (T B)]  {RH | (LH1 LH2)}
```

### The grammar

| Written | Means |
| --- | --- |
| `T1` | a voice, by the id its `V:` gave it |
| `(T1 T2)` | a **voice group** — these voices share one staff |
| `[ … ]` | a **bracket** joins the staves of everything inside it |
| `{ … }` | a **brace** joins them instead — keyboard music |
| `A \| B` | continued bar lines are drawn across the boundary between A and B |
| `*M` | a **floating** voice: no staff of its own, each note drawn on the staff above or below |

Brackets and braces nest, and a group may hold groups: `[{Vln1 | Vln2} | Vla | Vc | DB]` is
the string-section plan §11.1 gives as an example, and CeolKit draws it as written — the
outer bracket, the brace inside it, and continued bar lines at the three boundaries marked
with `|`.

`%%staves` accepts the same payload and inverts the sense of `|` alone, so `%%staves
[S|A|T|B]` and `%%score [S A T B]` are the same plan. Nothing downstream can tell which
spelling was used.

A payload CeolKit cannot parse — an unclosed group, a stray delimiter, something left over
after the end — produces a warning and the **whole directive is dropped**, which leaves the
tune laid out as though it had no plan. A partial plan would be a layout nobody wrote.

### Where a plan may be written

| Written in | Governs |
| --- | --- |
| the file header | every tune in the file, unless that tune writes its own |
| the tune header | the whole tune |
| the tune body | that stave onwards — §11.1's "resets the music generator" |

A body plan takes effect from the start of the **stave** (one source line of music, the unit
`Voice.staves` is indexed in) it is written in. A plan written half way through a stave is
snapped back to the start of it, with a `staffPlanSnappedToStave` warning. The staves of a
system are laid out together, so a plan cannot change part way through one without splitting
it, and snapping is more predictable than an implicit system break the source never asked
for. Each plan change starts a new system.

### Which voices are printed

§11.1: *"Any voices appearing in the tune body will only be printed if it is mentioned in the
score directive."* A plan therefore both filters and orders, and its order wins over `V:`
declaration order.

| Case | What happens |
| --- | --- |
| a voice the plan does not name | not printed; `voiceNotInStaffPlan` info diagnostic |
| a voice the plan names twice | printed once, where it is first named; `staffPlanVoiceRepeated` warning |
| a voice the plan names that the tune does not have | `staffPlanVoiceNotFound` warning, nothing drawn |
| a voice the plan names that is declared but never written to | quietly skipped — the plan is right and the body has nothing to say |
| a plan that selects no voice at all | `staffPlanEmpty` warning, and the tune is laid out as though it had no plan |

The last of those is the recovery contract at work: a `Score` always comes back, and a tune
whose plan selects nothing is more usefully drawn wrongly than not drawn at all.

---

## What the standard leaves open

### With no directive at all, every voice gets a staff — and the bar lines are continued

§11.1 says only that *"all voices that appear in the tune body are printed on separate
staves"*. It does not say whether their bar lines join.

CeolKit joins them. This is what `abcm2ps` draws, and it is what CeolKit drew before it
understood `%%score` at all, so no existing page moved when the directive arrived. Written
out, the default is `%%score [1|2|3]` rather than `%%score [1 2 3]`.

A `%%score` with no `|` in it therefore *removes* the continued bar lines a plainer tune
would have had. That is the standard's sense of `|` and not a CeolKit choice, but it
surprises people, and `%%staves` exists precisely because it surprised people before.

### The staves of a system are joined at the left edge, plan or no plan

Independently of any bracket or brace, a system of more than one staff is closed at its left
edge by a rule running from the top staff's top line to the bottom staff's bottom line. It
is drawn at the staff lines' own weight, so it reads as the staves' shared left edge rather
than as furniture, and `%%score` neither adds it nor takes it away.

### A shared staff takes its clef, key and name from the voice written first

Where `( … )` puts several voices on one staff, each of them may carry its own `V:` clef and
its own per-voice `K:`. Only one of those can be drawn at the head of the staff.

CeolKit draws the first-written voice's, throughout: the clef at the head of every system,
the key signature, and the `name=` / `snm=` in the gutter. The other tenants contribute their
notes, their `stem=` and their own `L:` — durations are read per voice, so a tenant written
at a different unit note length still lasts as long as it says it does — and nothing else.

**This differs from `abcm2ps`, which stacks the names** — it prints `Tenore I` over
`Tenore II` beside the shared tenor staff, where CeolKit prints `Tenore I` alone. Both are
conforming; §4.1 says the name is *"printed on the left of the first staff of the voice in
question"* and says nothing about what to do when two voices claim the same staff. CeolKit's
gutter reserves one line per staff, which is the choice this follows from.

### The head of every system draws the key that system opens in

§7.3 says a `K:` in the tune body changes the key from that point on, and says nothing about
what the *next* staff head draws. Every engraving convention repeats the key signature at the
head of every system, so CeolKit does — and repeats the key in force where that system starts,
not the one the voice was declared in. A tune that changes key half way through therefore
carries the new signature at the head of every system after the change, as printed music does.

Where a system opens *on* the bar the change lands in, the head is the change itself: the
naturals cancelling the outgoing signature, then the incoming one's accidentals. It is drawn
there and not again at the head of the bar, so the change is engraved once.

A time signature is not treated this way, and deliberately: `M:` is drawn where the meter
moves and never repeated at a line break, which is also standard practice.

### Everything about a floating voice

The standard names the outcome — each note on the staff above or the staff below — and gives
no rule for reaching it, and it explicitly permits software to give up and print the whole
voice on the preceding staff. CeolKit does the real thing, by a rule of its own invention:
the split pitch, the atom, the hysteresis. It is written up in
[EXTENSIONS.md → Floating voices](EXTENSIONS.md#floating-voices--how-the-staff-is-chosen)
because the rule is ours, not the standard's.

### Overlays and `%%score`

An `&` voice overlay (§7.4) is placed on the staff of the voice that wrote it, directly under
it, after the plan has been resolved. No `%%score` can name, place or leave out an overlay:
it belongs to its voice and goes wherever that voice goes.

---

## §11.4.7 Page breaks — `%%newpage`

**Syntax:** `%%newpage [<int>]` — start a new page, optionally renumbering it from `<int>`.

§11.4.7 lists `%%newpage` among the separation directives and §11.6 leaves the parameters to
the implementation; `abcm2ps` and `abc2svg` both answer to it, and CeolKit uses their
spelling — unprefixed, and with the same optional integer. §11.0.1 asks that a directive
implemented in more than one program converge rather than fork, and a file that page-breaks
correctly in `abcm2ps` should not need editing to page-break here.

### Where it may be written

| Written in | Breaks before |
| --- | --- |
| the file header | the first tune — which prints no break, since nothing has been engraved yet |
| the gap between two tunes | the tune below it |
| a tune header | that tune |
| the tune body | the stave it stands above |
| below a tune's last stave | whatever follows the tune |

Like a staff plan, a break in the body takes effect from the start of the **stave** (one
source line of music) it is written in, and one written part-way through a stave — between
the voices of a multi-voice system, say — snaps back to the start of it with a
`pageBreakSnappedToStave` warning. A page break is a system break, and the staves of a
system are laid out together, so it cannot fall part-way through one.

A `%%newpage` past the last tune in the file has nothing left to move onto a fresh page. It
is dropped, with a `pageBreakAfterLastTune` info diagnostic, rather than leaving a blank
page behind it — and for the same reason one at the very top of a file breaks nothing: an
empty page is not something to break away from.

### The optional page number

`%%newpage N` renumbers the page it opens to `N`, and the count carries on from there, so
the page after a `%%newpage 20` is 21. `N` must be an integer of 1 or more.

An argument that is not one — `%%newpage frog`, `%%newpage 0` — produces an
`invalidPageNumber` warning and **the page break still happens**; only the renumbering is
dropped. The argument is optional, so a bad one is a mistyped option on a directive that is
otherwise perfectly clear, and refusing to break the page would lose the part the author got
right.

The number reaches the `$P` and `${pagenumber}` footer substitutions and the `page` field of
the `ceolkit-meta` scroll-sync comment, exactly as
[`%%ceolkit:pagenumber`](EXTENSIONS.md#ceolkitpagenumber) does. The two compose: that
directive names the document's opening page, and each `%%newpage N` renames the one it
opens.

### What CeolKit does not do

`%%newpage` is the only one of §11.4.7's separation directives CeolKit implements. `%%sep`
and `%%vskip` are still reported as unsupported and ignored, which is what §11.0.2 asks of a
directive an application does not recognise.

---

## Worked examples in the test suite

The standard's own multi-voice examples are checked in end to end, parser and renderer, so
that what this document claims is what the code does:

| Example | Fixture |
| --- | --- |
| §7 Zocharti Loch — `%%score (T1 T2) (B1 B2)`, two voices to a staff | `ZochartiLochTests`, `ZochartiLochConformanceTests` |
| §14.4 Canzonetta — `%%score [1 2 3]`, three voices bracketed, two verses of lyrics | `CanzonettaTests`, `CanzonettaConformanceTests` |
