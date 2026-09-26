import Foundation
import CeolKitModel

/// Horizontal geometry of a grace-note group.
///
/// The sizer reserves the space and the emitter draws into it, so both derive their
/// numbers from here rather than from duplicated literals.
///
/// A group's box is laid out as
///
/// ```
/// |<-pad->|<-head->|<-advance->|<-head->|<-pad->|
/// ```
///
/// where `pad` is `edgePad × graceNoteheadWidth` at each outer edge and `advance` is the
/// step between adjacent noteheads.  Adjacent noteheads within a group sit on a shared beam
/// and are engraved nearly touching, so `advance` is close to one notehead width — much
/// tighter than the outer padding implies (see `SVGRenderConfig.graceNoteSpacing`).
///
/// A note carrying a displayed accidental is the exception: its accidental glyph is drawn to
/// the left of its notehead, so the step into it grows by whatever that glyph needs.
struct GraceMetrics {
    /// Scale factor for grace note glyphs and geometry relative to normal notes.
    static let scale = 0.6

    /// Padding at each outer edge of a group, in grace notehead widths.
    static let edgePad = 0.25

    /// Width of a grace notehead.
    let noteheadWidth: Double

    /// x of a stem's centreline from its notehead's left edge.  Grace stems always point up,
    /// so this is the notehead's `stemUpSE` anchor less half a stem (issue #181).
    let stemDX: Double

    /// How far above the notehead's centre its stem starts, from the same anchor.
    let stemBaseDY: Double

    /// Step between the x of one notehead and the next within the same group, for notes
    /// with no accidental.
    let advance: Double

    private let accidentalMetrics: AccidentalMetrics

    init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        let fullNoteheadWidth = metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                                ?? config.staffSize * 1.2
        self.noteheadWidth = fullNoteheadWidth * Self.scale
        let attachment = metadata.stemAttachment(to: .noteheadBlack, stemUp: true)
        self.stemDX = attachment.x * config.staffSize * Self.scale
        self.stemBaseDY = attachment.y * config.staffSize * Self.scale
        self.advance = self.noteheadWidth * config.graceNoteSpacing
        self.accidentalMetrics = AccidentalMetrics(config: config, metadata: metadata)
    }

    /// Space an accidental on `note` needs to the left of its notehead, at grace scale.
    private func accidentalSpace(_ note: Note) -> Double {
        accidentalMetrics.reservation(for: note.displayedAccidental, scale: Self.scale)
    }

    /// x of each notehead's left edge, relative to the group's left edge.
    func noteheadOffsets(_ notes: [Note]) -> [Double] {
        var x = 0.0
        var offsets: [Double] = []
        offsets.reserveCapacity(notes.count)
        for (i, note) in notes.enumerated() {
            let accSpace = accidentalSpace(note)
            if i == 0 {
                // Leading edge: an accidental on the first note needs at least its own
                // width before the notehead, otherwise the standard outer padding.
                x = max(noteheadWidth * Self.edgePad, accSpace)
            } else {
                // The previous note's stem sits at the right edge of its notehead, so an
                // accidental on this note has to clear that as well as the usual advance.
                x += max(advance, noteheadWidth + accSpace)
            }
            offsets.append(x)
        }
        return offsets
    }

    /// x of each note's stem, relative to the group's left edge.
    ///
    /// Grace stems always point up, so the stem sits just inside the right edge of the
    /// notehead, at ``stemDX``.
    func stemOffsets(_ notes: [Note]) -> [Double] {
        noteheadOffsets(notes).map { $0 + stemDX }
    }

    /// Total width of a grace group, from its left edge to the trailing pad after the last
    /// notehead's right edge.
    func width(_ notes: [Note]) -> Double {
        let last = noteheadOffsets(notes).last ?? (noteheadWidth * Self.edgePad)
        return last + noteheadWidth * (1 + Self.edgePad)
    }
}
