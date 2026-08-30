import CeolKitModel
import Foundation

// MARK: - Pass 1 output

public struct SizedMeasure: Sendable {
    public let measure: Measure
    /// Natural (un-justified) width in points.
    public let naturalWidth: Double
    /// X offset of each event in `measure.events`, relative to the measure origin.
    /// `eventOffsets.count == measure.events.count`.
    public let eventOffsets: [Double]
    /// The voice's `L:` unit note length, carried forward so Pass 5 can resolve
    /// absolute durations for notehead-type selection without extra context.
    public let unitNoteLength: Fraction
    /// Indices into `eventOffsets` that are grace events paired with the immediately
    /// following event.  The justifier keeps the gap within each such pair fixed so
    /// grace notes stay visually attached to their melody note when measures are stretched.
    public let graceEventIndices: Set<Int>
    /// The voice each event came from, parallel to `eventOffsets`.
    /// `eventVoiceIndices.count == eventOffsets.count`.
    ///
    /// The voice's position *within its own staff*, top to bottom — which staff that is, the
    /// enclosing ``System`` already says.  A staff carrying one voice therefore tags every
    /// event `0`; a shared staff (§11.1 `( … )`) is what makes this a per-event table rather
    /// than a property of the measure, and what the opposed stems and per-voice beaming above
    /// this pass read to tell its tenants apart.
    public let eventVoiceIndices: [Int]

    public init(
        measure: Measure,
        naturalWidth: Double,
        eventOffsets: [Double],
        unitNoteLength: Fraction = Fraction(numerator: 1, denominator: 8),
        graceEventIndices: Set<Int> = [],
        eventVoiceIndices: [Int]? = nil
    ) {
        self.measure = measure
        self.naturalWidth = naturalWidth
        self.eventOffsets = eventOffsets
        self.unitNoteLength = unitNoteLength
        self.graceEventIndices = graceEventIndices
        // Kept parallel by construction: a caller that says nothing about voices gets the
        // single-voice answer rather than an array the rest of the pipeline has to test.
        self.eventVoiceIndices = eventVoiceIndices
            ?? Array(repeating: 0, count: eventOffsets.count)
    }
}

// MARK: - Pass 2 output

public struct System: Sendable {
    public let measures: [SizedMeasure]
    public let isLastSystem: Bool
    /// `true` when the system break was forced by a `.hard` `ScoreLineBreak` in the source.
    public let sourceForced: Bool
    /// `true` when the source stave this system came from did not fit on one line and the
    /// line breaker split it.  The width of such a system is the packer's choice, not the
    /// engraver's, so the `Justifier` caps how far it will stretch one; a system whose width
    /// the source asked for is stretched to fill the line however short it is.
    public let staveWasSplit: Bool
    public let clef: ClefSpec
    public let keySignature: KeySignature?
    /// Non-nil only on the first system of a tune; time signatures do not repeat at line breaks.
    public let meter: Meter?
    /// What this voice prints in the left gutter of *this* system: its `V:` `name=` on the
    /// tune's first system, its `sname=` on every later one, and `nil` where it has none
    /// (ABC v2.2 §4.1).  A voice with a name but no subname is therefore labelled once and
    /// then not again, which is what abcm2ps does.
    public let voiceLabel: String?
    /// What each voice drawn on this staff asked for with `V:` `stem=` (§4.1, issue #74),
    /// in staff order.  One entry per voice: a staff carrying one voice has one entry, and a
    /// shared staff (§11.1 `( … )`) one per tenant.  `.auto` — the overwhelmingly common
    /// case — means that voice asked for nothing, and its position on the staff, then the
    /// document, then the note's own pitch decides (issue #77).
    public let voiceStemDirections: [StemDirection]

    /// What the staff's *first* voice asked for.  That is the whole answer for a staff
    /// carrying one voice, which is every staff until a `%%score` group shares one.
    public var stemDirection: StemDirection { voiceStemDirections.first ?? .auto }

    public init(
        measures: [SizedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        staveWasSplit: Bool = false,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil,
        voiceLabel: String? = nil,
        voiceStemDirections: [StemDirection] = []
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.staveWasSplit = staveWasSplit
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
        self.voiceLabel = voiceLabel
        self.voiceStemDirections = voiceStemDirections
    }
}

/// The brace/bracket spans and continued bar-line boundaries of one system, expressed in
/// *printed* staff indices — positions in ``SystemGroup/staves``.
///
/// `%%score` / `%%staves` states them over the staves of the *plan*, which are not the
/// staves that get printed: a voice the body never wrote to is dropped, and a floating `*V`
/// takes a staff of its own that the plan never counted.
/// ``VoiceSelector`` translates them as it selects, so everything below this point can read
/// the indices straight off.
///
/// `nil` on a group means the tune had no plan (or the selector fell back from one), and
/// every stage behaves exactly as it did before plans existed.
public struct StaffGrouping: Sendable {
    /// Outermost first.  May be empty: a plan can order the voices without grouping them.
    public let spans: [Span]
    /// Printed staff `i` is joined to `i + 1` by a bar line that runs through the gap.
    public let barlineJoins: Set<Int>

    public init(spans: [Span], barlineJoins: Set<Int>) {
        self.spans = spans
        self.barlineJoins = barlineJoins
    }

    public struct Span: Hashable, Sendable {
        public let bracket: StaffPlanBracket
        /// Printed staff indices, inclusive.
        public let staves: ClosedRange<Int>
        /// 0 = outermost; drives sub-bracket thickness.
        public let depth: Int

        public init(bracket: StaffPlanBracket, staves: ClosedRange<Int>, depth: Int) {
            self.bracket = bracket
            self.staves = staves
            self.depth = depth
        }
    }
}

/// One system's worth of unjustified music: the staves the voices active on the source line
/// the system came from are drawn on, top to bottom.
///
/// One staff per voice, except where a `%%score ( … )` group put several on one — those are
/// merged into a single staff before this point (see ``SharedStaffMerger``).  A single-voice
/// tune produces groups of exactly one staff, which is the pre-grouping path unchanged:
/// every stage below treats a one-staff group as an ordinary system.
public struct SystemGroup: Sendable {
    /// One entry per printed staff, top to bottom.  Never empty.
    ///
    /// Every staff holds the same number of measures and was broken at the same measure
    /// index, because `VoiceAligner` padded the voices into agreement before the line
    /// breaker ever saw them.
    public let staves: [System]

    /// The plan's spans and bar-line joins for this system, or `nil` when no plan governs
    /// it.  Identical on every group of one plan region, and free to differ between regions:
    /// a `%%score` in the tune body changes both the staves and how they are grouped (see
    /// `PlanRegions`).
    public let grouping: StaffGrouping?

    public init(staves: [System], grouping: StaffGrouping? = nil) {
        self.staves = staves
        self.grouping = grouping
    }

    /// The properties the line breaker assigned to the group as a whole.  They are recorded
    /// on every staff identically, so the first one speaks for all of them.
    public var isLastSystem: Bool { staves[0].isLastSystem }
    public var sourceForced: Bool { staves[0].sourceForced }
    public var staveWasSplit: Bool { staves[0].staveWasSplit }
    /// Number of measures in each staff — the group's column count.
    public var columnCount: Int { staves[0].measures.count }
}

/// Groups the justified systems and optional title block for a single tune.
///
/// `titleRows` use `baselineY` values relative to the top of the tune's title area
/// (i.e. `y = 0` origin). The layout engine adds the actual page y-origin when placing them,
/// so the same `TuneBlock` can be positioned anywhere on a page.
public struct TuneBlock: Sendable {
    /// One entry per system, each holding one staff per voice.
    public let systemGroups: [JustifiedSystemGroup]
    public let titleRows: [ResolvedTitleRow]
    public let titleBlockHeight: Double
    /// Multiplier applied to `SVGRenderConfig.staffSize` (and the inter-system/inter-tune gaps
    /// derived from it) for this tune's music, from `%%ceolkit:scale`.  `1.0` = renderer default.
    /// The title block is laid out in absolute points and is unaffected.
    public let scale: Double
    /// Step between adjacent grace noteheads in this tune's grace groups, in grace notehead
    /// widths, from `%%ceolkit:gracenotespacing`.  A ratio, not a size: unlike `scale` it is
    /// carried through unmultiplied.  The sizer reserved the group's width with this value,
    /// so the emitter has to draw with the same one.
    public let graceNoteSpacing: Double

    public init(systemGroups: [JustifiedSystemGroup], titleRows: [ResolvedTitleRow] = [],
                titleBlockHeight: Double = 0, scale: Double = 1.0,
                graceNoteSpacing: Double = SVGRenderConfig().graceNoteSpacing) {
        self.systemGroups = systemGroups
        self.titleRows = titleRows
        self.titleBlockHeight = titleBlockHeight
        self.scale = scale
        self.graceNoteSpacing = graceNoteSpacing
    }

    /// Convenience for single-voice music: each system becomes a group of one staff.
    public init(systems: [JustifiedSystem], titleRows: [ResolvedTitleRow] = [],
                titleBlockHeight: Double = 0, scale: Double = 1.0,
                graceNoteSpacing: Double = SVGRenderConfig().graceNoteSpacing) {
        self.init(systemGroups: systems.map { JustifiedSystemGroup(staves: [$0]) },
                  titleRows: titleRows, titleBlockHeight: titleBlockHeight,
                  scale: scale, graceNoteSpacing: graceNoteSpacing)
    }
}

// MARK: - Pass 3 output

/// A `SystemGroup` after justification.
///
/// Every staff carries the same per-column final widths, so a bar line at column *j* lands
/// on the same x on all of them — which is the whole point of engraving voices in parallel.
public struct JustifiedSystemGroup: Sendable {
    /// One entry per voice, top to bottom.  Never empty.
    public let staves: [JustifiedSystem]

    /// Carried through from ``SystemGroup/grouping`` — justification changes x positions,
    /// never which staves a brace or bracket covers.
    public let grouping: StaffGrouping?

    public init(staves: [JustifiedSystem], grouping: StaffGrouping? = nil) {
        self.staves = staves
        self.grouping = grouping
    }

    public var isLastSystem: Bool { staves[0].isLastSystem }
    public var sourceForced: Bool { staves[0].sourceForced }
}

public struct JustifiedSystem: Sendable {
    public let measures: [JustifiedMeasure]
    public let isLastSystem: Bool
    public let sourceForced: Bool
    public let clef: ClefSpec
    public let keySignature: KeySignature?
    /// Non-nil only on the first system of a tune; time signatures do not repeat at line breaks.
    public let meter: Meter?
    /// Carried through from ``System/voiceLabel`` — justification moves x positions, never
    /// what a staff is called.
    public let voiceLabel: String?
    /// Carried through from ``System/voiceStemDirections`` — justification moves x
    /// positions, never which way a voice's stems point.
    public let voiceStemDirections: [StemDirection]

    /// What the staff's first voice asked for; see ``System/stemDirection``.
    public var stemDirection: StemDirection { voiceStemDirections.first ?? .auto }

    public init(
        measures: [JustifiedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil,
        voiceLabel: String? = nil,
        voiceStemDirections: [StemDirection] = []
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
        self.voiceLabel = voiceLabel
        self.voiceStemDirections = voiceStemDirections
    }
}

public struct JustifiedMeasure: Sendable {
    public let source: SizedMeasure
    /// Final rendered width in points.  Usually ≥ `source.naturalWidth`, but a system the
    /// line breaker let overrun the line within its overflow tolerance is compressed to fit,
    /// so this can be slightly smaller.
    public let finalWidth: Double
    /// Event x-offsets after justification.  Grace-to-note gaps are held at their natural
    /// size; all remaining horizontal slack is distributed among elastic (note-to-note) spacings.
    public let eventOffsets: [Double]

    public init(source: SizedMeasure, finalWidth: Double, eventOffsets: [Double]) {
        self.source = source
        self.finalWidth = finalWidth
        self.eventOffsets = eventOffsets
    }

    /// The voice tags of ``SizedMeasure/eventVoiceIndices``, still parallel to
    /// ``eventOffsets``.  Justification moves events along the line; it never adds, drops or
    /// reorders one, so the sizer's table is as valid after it as before.
    public var eventVoiceIndices: [Int] { source.eventVoiceIndices }
}

// MARK: - Pass 4 output

public struct ResolvedLayout: Sendable {
    public let pageSize: Size
    public let margins: EdgeInsets
    public let pages: [ResolvedPage]

    public init(pageSize: Size, margins: EdgeInsets, pages: [ResolvedPage]) {
        self.pageSize = pageSize
        self.margins = margins
        self.pages = pages
    }
}

public struct ResolvedPage: Sendable {
    public let systems: [ResolvedSystem]
    /// Pre-positioned title rows; non-empty on any page that starts a tune.
    public let titleRows: [ResolvedTitleRow]
    /// Pre-positioned footer rows; present on every page that has a %%footer template.
    public let footerRows: [ResolvedTitleRow]

    public init(systems: [ResolvedSystem], titleRows: [ResolvedTitleRow] = [],
                footerRows: [ResolvedTitleRow] = []) {
        self.systems = systems
        self.titleRows = titleRows
        self.footerRows = footerRows
    }
}

/// A single rendered row in the title block, with absolute page coordinates.
public struct ResolvedTitleRow: Sendable {
    public struct Item: Sendable {
        public let text: String
        public let x: Double
        public let baselineY: Double
        public let anchor: TextAnchor
        public let fontSize: Double
        public let isItalic: Bool

        public init(text: String, x: Double, baselineY: Double,
                    anchor: TextAnchor, fontSize: Double, isItalic: Bool = false) {
            self.text = text
            self.x = x
            self.baselineY = baselineY
            self.anchor = anchor
            self.fontSize = fontSize
            self.isItalic = isItalic
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

public enum TextAnchor: String, Sendable {
    case start, middle, end
}

/// Where one staff sits inside a multi-staff system, and how far the furniture that belongs
/// to the *group* rather than to this staff has to reach.
///
/// Present only when the system holds more than one voice.  A single-voice tune leaves
/// ``ResolvedSystem/staffGroup`` nil and the emitter takes exactly the path it always did.
public struct StaffGroup: Sendable {
    /// 0-based position of this staff within its group, top to bottom.
    public let index: Int
    /// Number of staves in the group.  Always > 1 — a group of one is represented by `nil`.
    public let count: Int
    /// Absolute y of the *next* staff's top staff line, or `nil` on the group's last staff.
    ///
    /// Where ``continuesBarlineBelow`` is set, bar lines are drawn down to this instead of
    /// stopping at their own staff, so the joined staves' bar lines read as one continuous
    /// stroke.  Repeat dots still sit within the staff that owns them.
    public let nextStaffTopY: Double?
    /// Absolute y of the bottom staff line of the group's last staff — the foot of the
    /// vertical line that joins the staves at the left edge.
    public let bottomY: Double
    /// The brace/bracket spans that *begin* at this staff, outermost first, resolved to
    /// absolute y.  Empty on a staff no span starts at, and on every staff of a group whose
    /// tune has no plan.
    ///
    /// Anchored on the first staff rather than listed on every staff it covers, because that
    /// is the staff which draws the furniture spanning a group — see ``isGroupLeader``.  Two
    /// spans can start on the same staff (`[{A B} C]`), so this is a list and not a single
    /// bracket kind.
    public let spans: [Span]
    /// Whether the bar line at the boundary *below* this staff runs on into the next one.
    /// Always `false` on the group's last staff.
    ///
    /// With no plan every boundary continues, which is the behaviour multi-voice systems
    /// have had since they were introduced.  A plan states the boundaries it wants with `|`
    /// and the rest stop at their own staff (issue #68).
    public let continuesBarlineBelow: Bool

    /// One brace or bracket, placed on the page.
    public struct Span: Sendable {
        public let bracket: StaffPlanBracket
        /// Indices within the group, inclusive.  `lowerBound` is the staff carrying this span.
        public let staves: ClosedRange<Int>
        /// 0 = outermost; drives sub-bracket thickness.
        public let depth: Int
        /// Absolute x of the left edge of the span's vertical spine.  Left of the staves,
        /// in the indent ``BracketColumns`` reserved for it — the deeper the span, the
        /// closer to them.
        public let x: Double
        /// Absolute y of the top staff line of the span's first staff.
        public let topY: Double
        /// Absolute y of the bottom staff line of the span's last staff.
        public let bottomY: Double

        public init(bracket: StaffPlanBracket, staves: ClosedRange<Int>, depth: Int,
                    x: Double, topY: Double, bottomY: Double) {
            self.bracket = bracket
            self.staves = staves
            self.depth = depth
            self.x = x
            self.topY = topY
            self.bottomY = bottomY
        }
    }

    public init(index: Int, count: Int, nextStaffTopY: Double?, bottomY: Double,
                spans: [Span] = [], continuesBarlineBelow: Bool = false) {
        self.index = index
        self.count = count
        self.nextStaffTopY = nextStaffTopY
        self.bottomY = bottomY
        self.spans = spans
        self.continuesBarlineBelow = continuesBarlineBelow
    }

    /// `true` on the staff that draws the furniture spanning the whole group.
    public var isGroupLeader: Bool { index == 0 }
}

/// A voice's `V:` `name=` / `sname=`, placed on the page.
///
/// The text and its x arrive together because the x is not derived from the staff: it is
/// the right edge of the gutter ``VoiceLabelGutter`` reserved for the *system*, which is
/// as far left as the widest label in it reaches.  Every staff of a system shares that
/// edge, so the labels right-align with each other rather than each ending where its own
/// staff begins.
public struct VoiceLabel: Sendable {
    public let text: String
    /// Absolute x the label is right-aligned against.
    public let x: Double

    public init(text: String, x: Double) {
        self.text = text
        self.x = x
    }
}

public struct ResolvedSystem: Sendable {
    public let origin: Point
    public let measures: [ResolvedMeasure]
    /// Y offset of the top staff line relative to `origin.y`.
    public let staffOrigin: Double
    /// Distance between adjacent staff lines, after `%%ceolkit:scale` has been applied.
    /// The emitter derives every glyph and stem dimension in this system from it.
    public let staffSize: Double
    /// Height of the staff body: 4 × staffSize (five lines, four spaces).
    public let staffHeight: Double
    /// Step between adjacent grace noteheads, in grace notehead widths, from
    /// `%%ceolkit:gracenotespacing`.  Travels with the system for the same reason
    /// `staffSize` does: it is set per tune, and one page can hold systems from several.
    public let graceNoteSpacing: Double
    /// Space above the top staff line (ledger lines, chord symbols, annotations).
    public let extraAbove: Double
    /// Space below the bottom staff line (ledger lines, lyrics).
    public let extraBelow: Double
    /// `extraAbove + staffHeight + extraBelow`.
    public let totalHeight: Double
    public let clef: ClefSpec
    public let keySignature: KeySignature?
    /// Non-nil only on the first system of a tune; time signatures do not repeat at line breaks.
    public let meter: Meter?
    /// 1-based ABC source line that first contributed content to this staff system.
    /// Used to emit scroll-sync anchor metadata (see `%%ceolkit` extension, issue #25).
    ///
    /// In a multi-voice system every staff reports the *group's* line — the first voice's —
    /// rather than its own, so the anchor sequence down a page stays monotonic (issue #41).
    public let abcLine: Int
    /// Non-nil when this staff is one of several in a system; see ``StaffGroup``.
    public let staffGroup: StaffGroup?
    /// The voice name drawn in this system's left gutter, already placed.  `nil` where the
    /// voice has nothing to print on this system, which is every voice of every tune that
    /// names none.
    public let voiceLabel: VoiceLabel?
    /// What each voice drawn on this staff asked for with `V:` `stem=`, in staff order —
    /// one entry per voice, so its count is also how many voices share the staff.  A voice
    /// that states a direction overrides both the automatic opposition of a shared staff and
    /// `%%ceolkit:pipeformat`; `.auto` leaves the choice to the voice's position on the
    /// staff, then the document, then the note's own staff position.
    public let voiceStemDirections: [StemDirection]

    /// What the staff's first voice asked for; see ``System/stemDirection``.
    public var stemDirection: StemDirection { voiceStemDirections.first ?? .auto }

    public init(
        origin: Point,
        measures: [ResolvedMeasure],
        staffOrigin: Double,
        staffSize: Double,
        staffHeight: Double,
        graceNoteSpacing: Double = SVGRenderConfig().graceNoteSpacing,
        extraAbove: Double,
        extraBelow: Double,
        totalHeight: Double,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil,
        abcLine: Int = 1,
        staffGroup: StaffGroup? = nil,
        voiceLabel: VoiceLabel? = nil,
        voiceStemDirections: [StemDirection] = []
    ) {
        self.origin = origin
        self.measures = measures
        self.staffOrigin = staffOrigin
        self.staffSize = staffSize
        self.staffHeight = staffHeight
        self.graceNoteSpacing = graceNoteSpacing
        self.extraAbove = extraAbove
        self.extraBelow = extraBelow
        self.totalHeight = totalHeight
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
        self.abcLine = abcLine
        self.staffGroup = staffGroup
        self.voiceLabel = voiceLabel
        self.voiceStemDirections = voiceStemDirections
    }
}

public struct ResolvedMeasure: Sendable {
    public let origin: Point
    public let width: Double
    public let events: [ResolvedEvent]
    public let openingBar: ResolvedBarLine?
    public let closingBar: ResolvedBarLine
    /// Propagated from `SizedMeasure.unitNoteLength`; used by the emitter to compute
    /// absolute note durations for notehead-type selection.
    public let unitNoteLength: Fraction
    /// Non-nil when an inline `[M:…]` changed the time signature before this measure.
    /// The emitter draws the corresponding glyph at `origin.x` before the first note.
    public let meter: Meter?

    public init(
        origin: Point,
        width: Double,
        events: [ResolvedEvent],
        openingBar: ResolvedBarLine?,
        closingBar: ResolvedBarLine,
        unitNoteLength: Fraction = Fraction(numerator: 1, denominator: 8),
        meter: Meter? = nil
    ) {
        self.origin = origin
        self.width = width
        self.events = events
        self.openingBar = openingBar
        self.closingBar = closingBar
        self.unitNoteLength = unitNoteLength
        self.meter = meter
    }
}

public struct ResolvedBarLine: Sendable {
    /// Absolute x coordinate in page coordinates.
    public let x: Double
    public let kind: BarLineKind

    public init(x: Double, kind: BarLineKind) {
        self.x = x
        self.kind = kind
    }
}

public struct ResolvedEvent: Sendable {
    /// Absolute position in page coordinates; y is at the top staff line.
    public let origin: Point
    public let kind: ResolvedEventKind
    /// The voice this event was written by, carried through from
    /// ``SizedMeasure/eventVoiceIndices``: its position within the staff it is drawn on.
    /// With one voice per staff every event is `0`; a shared staff is where they differ.
    public let voiceIndex: Int

    public init(origin: Point, kind: ResolvedEventKind, voiceIndex: Int = 0) {
        self.origin = origin
        self.kind = kind
        self.voiceIndex = voiceIndex
    }
}

public enum ResolvedEventKind: Sendable {
    case note(Note)
    case rest(Rest)
    case chord(Chord)
    case grace(GraceGroup)
    case tuplet(Tuplet)
    case spacer(Spacer)
    case directiveAnchor(CeolKitDirective)
    case tempoChange(Tempo)

    init(from event: Event) {
        switch event {
        case .note(let n):            self = .note(n)
        case .rest(let r):            self = .rest(r)
        case .chord(let c):           self = .chord(c)
        case .grace(let g):           self = .grace(g)
        case .tuplet(let t):          self = .tuplet(t)
        case .spacer(let s):          self = .spacer(s)
        case .directiveAnchor(let d): self = .directiveAnchor(d)
        case .tempoChange(let t):     self = .tempoChange(t)
        }
    }
}
