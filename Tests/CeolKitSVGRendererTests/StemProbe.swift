import CeolKitModel
@testable import CeolKitSVGRenderer

/// One drawn stem, with its direction recovered from where its notehead sits.
///
/// Direction is read out of the emitted document rather than out of the layout: a stem is
/// drawn from its notehead, so the end that coincides with a notehead's y is the notehead
/// end, and the stem points away from it.
struct ProbedStem {
    let x: Double
    let noteheadY: Double
    let tipY: Double
    var isUp: Bool { tipY < noteheadY }
}

/// Every stem in `svg`, paired with the notehead it grows from.
///
/// Stems are the `<line>`s at Bravura's stem thickness — thinner than every staff line and
/// bar line in the document, which is what ``BravuraMetadataTests`` pins.  Noteheads are the
/// Bravura `<text>` runs, so the renderer must be driven in `.fontFace` mode (see
/// ``textProbeRenderer(_:)``) to keep them readable as text.
func probedStems(in svg: String, staffSize: Double, metadata: BravuraMetadata) -> [ProbedStem] {
    let stemWidth = metadata.engravingDefaults.stemThickness * staffSize
    let noteheads = svg.matches(
        of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="Bravura"[^>]*>(.)<\/text>/
    ).compactMap { match -> (x: Double, y: Double)? in
        let heads: Set<Character> = [SMuFLGlyph.noteheadBlack.character,
                                     SMuFLGlyph.noteheadHalf.character,
                                     SMuFLGlyph.noteheadWhole.character]
        guard let x = Double(match.1), let y = Double(match.2),
              let ch = String(match.3).first, heads.contains(ch) else { return nil }
        return (x, y)
    }

    return svg.matches(
        of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)" y2="([-0-9.]+)" stroke="black" stroke-width="([-0-9.]+)"\/>/
    ).compactMap { match -> ProbedStem? in
        guard let x = Double(match.1), let y1 = Double(match.2),
              let y2 = Double(match.4), let width = Double(match.5),
              abs(width - stemWidth) < 0.01, y1 != y2 else { return nil }
        // The notehead end is whichever end a notehead is drawn at.  A stem is attached to
        // the right of its notehead when it points up and to the left when it points down,
        // so the x match has to allow a notehead's width either way.
        let touches: (Double) -> Bool = { end in
            noteheads.contains { abs($0.y - end) < 0.01 && abs($0.x - x) < 4 * staffSize }
        }
        if touches(y2) { return ProbedStem(x: x, noteheadY: y2, tipY: y1) }
        if touches(y1) { return ProbedStem(x: x, noteheadY: y1, tipY: y2) }
        return nil
    }
}

/// The stems of `svg` split into `bucketCount` groups by pitch, highest group first.
///
/// Written for music whose parts do not cross: every note of the upper part is higher than
/// every note of the lower one, so sorting by notehead y and cutting into equal groups
/// separates them exactly.  That holds both for two staves of a system — where the staves
/// are far apart vertically — and for two voices sharing one staff, which is what makes the
/// same probe serve both.
func probedStemsByPitchGroup(in svg: String, staffSize: Double, metadata: BravuraMetadata,
                             bucketCount: Int) -> [[ProbedStem]] {
    let sorted = probedStems(in: svg, staffSize: staffSize, metadata: metadata)
        .sorted { $0.noteheadY < $1.noteheadY }
    guard bucketCount > 1, !sorted.isEmpty else { return [sorted.sorted { $0.x < $1.x }] }
    let perBucket = sorted.count / bucketCount
    return (0..<bucketCount).map { bucket in
        Array(sorted[(bucket * perBucket)..<((bucket + 1) * perBucket)]).sorted { $0.x < $1.x }
    }
}
