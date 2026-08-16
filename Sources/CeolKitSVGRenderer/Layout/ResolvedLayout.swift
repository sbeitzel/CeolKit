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

    public init(
        measure: Measure,
        naturalWidth: Double,
        eventOffsets: [Double],
        unitNoteLength: Fraction = Fraction(numerator: 1, denominator: 8),
        graceEventIndices: Set<Int> = []
    ) {
        self.measure = measure
        self.naturalWidth = naturalWidth
        self.eventOffsets = eventOffsets
        self.unitNoteLength = unitNoteLength
        self.graceEventIndices = graceEventIndices
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

    public init(
        measures: [SizedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        staveWasSplit: Bool = false,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.staveWasSplit = staveWasSplit
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
    }
}

/// One system's worth of unjustified music: the staves of every voice that is active on
/// the source line the system came from, in `V:` declaration order.
///
/// A single-voice tune produces groups of exactly one staff, which is the pre-grouping
/// path unchanged — every stage below treats a one-staff group as an ordinary system.
public struct SystemGroup: Sendable {
    /// One entry per voice, top to bottom.  Never empty.
    ///
    /// Every staff holds the same number of measures and was broken at the same measure
    /// index, because `VoiceAligner` padded the voices into agreement before the line
    /// breaker ever saw them.
    public let staves: [System]

    public init(staves: [System]) {
        self.staves = staves
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

    public init(staves: [JustifiedSystem]) {
        self.staves = staves
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

    public init(
        measures: [JustifiedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
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
    /// Bar lines are drawn down to this instead of stopping at their own staff, so the
    /// group's bar lines read as one continuous stroke through the whole system.  Repeat
    /// dots still sit within the staff that owns them.
    public let nextStaffTopY: Double?
    /// Absolute y of the bottom staff line of the group's last staff — the foot of the
    /// vertical line that joins the staves at the left edge.
    public let bottomY: Double

    public init(index: Int, count: Int, nextStaffTopY: Double?, bottomY: Double) {
        self.index = index
        self.count = count
        self.nextStaffTopY = nextStaffTopY
        self.bottomY = bottomY
    }

    /// `true` on the staff that draws the furniture spanning the whole group.
    public var isGroupLeader: Bool { index == 0 }
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
        staffGroup: StaffGroup? = nil
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

    public init(origin: Point, kind: ResolvedEventKind) {
        self.origin = origin
        self.kind = kind
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
