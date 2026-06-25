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
    public let clef: ClefSpec
    public let keySignature: KeySignature?
    /// Non-nil only on the first system of a tune; time signatures do not repeat at line breaks.
    public let meter: Meter?

    public init(
        measures: [SizedMeasure],
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

/// Groups the justified systems and optional title block for a single tune.
///
/// `titleRows` use `baselineY` values relative to the top of the tune's title area
/// (i.e. `y = 0` origin). The layout engine adds the actual page y-origin when placing them,
/// so the same `TuneBlock` can be positioned anywhere on a page.
public struct TuneBlock: Sendable {
    public let systems: [JustifiedSystem]
    public let titleRows: [ResolvedTitleRow]
    public let titleBlockHeight: Double

    public init(systems: [JustifiedSystem], titleRows: [ResolvedTitleRow] = [], titleBlockHeight: Double = 0) {
        self.systems = systems
        self.titleRows = titleRows
        self.titleBlockHeight = titleBlockHeight
    }
}

// MARK: - Pass 3 output

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
    /// Final rendered width in points; always ≥ `source.naturalWidth`.
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

public struct ResolvedSystem: Sendable {
    public let origin: Point
    public let measures: [ResolvedMeasure]
    /// Y offset of the top staff line relative to `origin.y`.
    public let staffOrigin: Double
    /// Height of the staff body: 4 × staffSize (five lines, four spaces).
    public let staffHeight: Double
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

    public init(
        origin: Point,
        measures: [ResolvedMeasure],
        staffOrigin: Double,
        staffHeight: Double,
        extraAbove: Double,
        extraBelow: Double,
        totalHeight: Double,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil,
        meter: Meter? = nil
    ) {
        self.origin = origin
        self.measures = measures
        self.staffOrigin = staffOrigin
        self.staffHeight = staffHeight
        self.extraAbove = extraAbove
        self.extraBelow = extraBelow
        self.totalHeight = totalHeight
        self.clef = clef
        self.keySignature = keySignature
        self.meter = meter
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

    init(from event: Event) {
        switch event {
        case .note(let n):            self = .note(n)
        case .rest(let r):            self = .rest(r)
        case .chord(let c):           self = .chord(c)
        case .grace(let g):           self = .grace(g)
        case .tuplet(let t):          self = .tuplet(t)
        case .spacer(let s):          self = .spacer(s)
        case .directiveAnchor(let d): self = .directiveAnchor(d)
        }
    }
}
