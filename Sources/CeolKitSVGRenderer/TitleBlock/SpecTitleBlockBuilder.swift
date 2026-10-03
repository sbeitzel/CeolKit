import CeolKitModel

/// Builds a title block following the ABC v2.2 §6.1.3 typesetting rules.
///
/// Layout (top to bottom):
///   - First T: field — centered, large font; X: reference left-aligned on the same row if enabled
///   - Additional T: fields — centered, small italic (alternative titles)
///   - Rhythm/Composer rows: R: left-aligned on the first; each C: right-aligned on a row of
///     its own (§6.1.3), with O: appended in parens to the last
///
/// Fields not present in `writeFields` are omitted. An empty result means no title block.
struct SpecTitleBlockBuilder {
    let tune: Tune
    let writeFields: WriteFieldsConfig
    let layoutConfig: SVGRenderConfig
    /// How the tune's text is set (issue #186).  The defaults are the sizes and faces the
    /// title block has always used.
    var styles: TextStyles? = nil

    func build() -> (rows: [ResolvedTitleRow], height: Double) {
        let lineHeight    = layoutConfig.staffSize * 2.5
        let styles = self.styles ?? .standard(staffSize: layoutConfig.staffSize)
        let defaults = TextStyles.standard(staffSize: layoutConfig.staffSize)
        // The reference number is set as the info fields used to be, whatever they become.
        let referenceStyle = TextStyle(size: defaults.info.size)

        let leftX   = layoutConfig.margins.left
        let centerX = layoutConfig.pageSize.width / 2.0
        let rightX  = layoutConfig.pageSize.width - layoutConfig.margins.right

        var rows: [ResolvedTitleRow] = []
        // Height the rows so far have taken beyond the standard line each.  A row is the
        // standard line tall at its default size and grows in proportion past it, so a
        // directive's 30-point title does not run into the line below; at the defaults this
        // stays zero and every baseline is where it always was.
        var extra = 0.0

        /// The baseline of the next row, set in text `size` points where `defaultSize` is
        /// what that row is ordinarily set in; reserves the row's height.
        func nextBaseline(size: Double, defaultSize: Double) -> Double {
            let rowExtra = lineHeight * max(1, size / defaultSize) - lineHeight
            let baseline = lineHeight * Double(rows.count + 1) - lineHeight * 0.25
                + extra + rowExtra * 0.75
            extra += rowExtra
            return baseline
        }

        // Title rows: first T large, subsequent T small italic (alternative titles).
        if writeFields.includes("T") {
            for (index, title) in tune.titles.enumerated() {
                let isFirst = index == 0
                let style = isFirst ? styles.title : styles.subtitle
                let baselineY = nextBaseline(
                    size: style.size,
                    defaultSize: isFirst ? defaults.title.size : defaults.subtitle.size)

                var items: [ResolvedTitleRow.Item] = []

                // Reference number on the first title row, left-aligned.
                if isFirst && writeFields.includes("X") && tune.reference > 0 {
                    items.append(ResolvedTitleRow.Item(
                        text: String(tune.reference),
                        x: leftX, baselineY: baselineY, anchor: .start, style: referenceStyle))
                }

                items.append(ResolvedTitleRow.Item(
                    text: title.value,
                    x: centerX, baselineY: baselineY, anchor: .middle, style: style))

                rows.append(ResolvedTitleRow(items: items))
            }
        }

        // Rhythm / Composer rows.  Each composer gets a row of its own (§6.1.3); the rhythm
        // shares the first, and repeated R: fields are joined with `;` (§3).  The origin
        // follows the last composer, so it reads as qualifying the whole list.
        let rhythm = writeFields.includes("R")
            ? tune.metadata.rhythm.map(\.value).filter { !$0.isEmpty }.joined(separator: "; ")
            : ""
        var composers = writeFields.includes("C")
            ? tune.metadata.composer.map(\.value).filter { !$0.isEmpty }
            : []
        if !composers.isEmpty, writeFields.includes("O"),
           let origin = tune.metadata.origin.first, !origin.isEmpty {
            composers[composers.count - 1] += " (\(origin))"
        }

        for line in 0..<max(rhythm.isEmpty ? 0 : 1, composers.count) {
            let hasRhythm = line == 0 && !rhythm.isEmpty
            let hasComposer = line < composers.count
            // The row is as tall as the larger of what it holds.
            let size = max(hasRhythm ? styles.info.size : 0,
                           hasComposer ? styles.composer.size : 0)
            let baselineY = nextBaseline(size: size, defaultSize: defaults.composer.size)
            var items: [ResolvedTitleRow.Item] = []

            if hasRhythm {
                items.append(ResolvedTitleRow.Item(
                    text: rhythm, x: leftX, baselineY: baselineY, anchor: .start,
                    style: styles.info))
            }

            if hasComposer {
                items.append(ResolvedTitleRow.Item(
                    text: composers[line], x: rightX, baselineY: baselineY, anchor: .end,
                    style: styles.composer))
            }

            rows.append(ResolvedTitleRow(items: items))
        }

        // Tempo row (Q: field).
        if writeFields.includes("Q"), let tempo = tune.tempo {
            let tempoText = tempoAnnotationText(tempo)
            if !tempoText.isEmpty {
                let baselineY = nextBaseline(size: styles.tempo.size,
                                             defaultSize: defaults.tempo.size)
                rows.append(ResolvedTitleRow(items: [
                    ResolvedTitleRow.Item(
                        text: tempoText, x: leftX, baselineY: baselineY, anchor: .start,
                        style: styles.tempo)
                ]))
            }
        }

        guard !rows.isEmpty else { return ([], 0) }
        let totalHeight = lineHeight * Double(rows.count) + layoutConfig.staffSize + extra
        return (rows, totalHeight)
    }
}
