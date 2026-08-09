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
/// the left of its notehead, so it needs the wider `accidentalAdvance` to keep clear of the
/// preceding note.
struct GraceMetrics {
    /// Scale factor for grace note glyphs and geometry relative to normal notes.
    static let scale = 0.6

    /// Padding at each outer edge of a group, in grace notehead widths.
    static let edgePad = 0.25

    /// Step for a note whose notehead is preceded by an accidental glyph, in grace
    /// notehead widths.  Accidental placement within the group is unchanged from before
    /// grace groups were tightened, so this keeps the space that placement assumes.
    static let accidentalAdvance = 1.5

    /// Width of a grace notehead.
    let noteheadWidth: Double

    /// Step between the x of one notehead and the next within the same group.
    let advance: Double

    init(config: SVGRenderConfig, metadata: BravuraMetadata) {
        let fullNoteheadWidth = metadata.glyphBBoxes["noteheadBlack"].map { $0.width * config.staffSize }
                                ?? config.staffSize * 1.2
        self.noteheadWidth = fullNoteheadWidth * Self.scale
        self.advance = self.noteheadWidth * config.graceNoteSpacing
    }

    /// x of each notehead's left edge, relative to the group's left edge.
    func noteheadOffsets(_ notes: [Note]) -> [Double] {
        var x = noteheadWidth * Self.edgePad
        var offsets: [Double] = []
        offsets.reserveCapacity(notes.count)
        for (i, note) in notes.enumerated() {
            if i > 0 {
                x += note.displayedAccidental != nil ? noteheadWidth * Self.accidentalAdvance : advance
            }
            offsets.append(x)
        }
        return offsets
    }

    /// x of each note's stem, relative to the group's left edge.
    ///
    /// Grace stems always point up, so the stem sits at the right edge of the notehead.
    func stemOffsets(_ notes: [Note]) -> [Double] {
        noteheadOffsets(notes).map { $0 + noteheadWidth }
    }

    /// Total width of a grace group.
    func width(_ notes: [Note]) -> Double {
        let last = stemOffsets(notes).last ?? (noteheadWidth * (Self.edgePad + 1))
        return last + noteheadWidth * Self.edgePad
    }
}
