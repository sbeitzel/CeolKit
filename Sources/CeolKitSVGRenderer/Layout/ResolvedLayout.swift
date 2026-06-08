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

    public init(
        measure: Measure,
        naturalWidth: Double,
        eventOffsets: [Double],
        unitNoteLength: Fraction = Fraction(numerator: 1, denominator: 8)
    ) {
        self.measure = measure
        self.naturalWidth = naturalWidth
        self.eventOffsets = eventOffsets
        self.unitNoteLength = unitNoteLength
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

    public init(
        measures: [SizedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.clef = clef
        self.keySignature = keySignature
    }
}

// MARK: - Pass 3 output

public struct JustifiedSystem: Sendable {
    public let measures: [JustifiedMeasure]
    public let isLastSystem: Bool
    public let sourceForced: Bool
    public let clef: ClefSpec
    public let keySignature: KeySignature?

    public init(
        measures: [JustifiedMeasure],
        isLastSystem: Bool,
        sourceForced: Bool,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil
    ) {
        self.measures = measures
        self.isLastSystem = isLastSystem
        self.sourceForced = sourceForced
        self.clef = clef
        self.keySignature = keySignature
    }
}

public struct JustifiedMeasure: Sendable {
    public let source: SizedMeasure
    /// Final rendered width in points; always ≥ `source.naturalWidth`.
    public let finalWidth: Double
    /// Event x-offsets rescaled from `source.eventOffsets` by `finalWidth / naturalWidth`.
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

    public init(systems: [ResolvedSystem]) {
        self.systems = systems
    }
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

    public init(
        origin: Point,
        measures: [ResolvedMeasure],
        staffOrigin: Double,
        staffHeight: Double,
        extraAbove: Double,
        extraBelow: Double,
        totalHeight: Double,
        clef: ClefSpec = ClefSpec(clef: .treble, octaveShift: 0),
        keySignature: KeySignature? = nil
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

    public init(
        origin: Point,
        width: Double,
        events: [ResolvedEvent],
        openingBar: ResolvedBarLine?,
        closingBar: ResolvedBarLine,
        unitNoteLength: Fraction = Fraction(numerator: 1, denominator: 8)
    ) {
        self.origin = origin
        self.width = width
        self.events = events
        self.openingBar = openingBar
        self.closingBar = closingBar
        self.unitNoteLength = unitNoteLength
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
