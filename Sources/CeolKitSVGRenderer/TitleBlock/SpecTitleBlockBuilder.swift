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

    func build() -> (rows: [ResolvedTitleRow], height: Double) {
        let lineHeight    = layoutConfig.staffSize * 2.5
        let titleFontSize = 18.0
        let infoFontSize  = 12.0

        let leftX   = layoutConfig.margins.left
        let centerX = layoutConfig.pageSize.width / 2.0
        let rightX  = layoutConfig.pageSize.width - layoutConfig.margins.right

        var rows: [ResolvedTitleRow] = []

        // Title rows: first T large, subsequent T small italic (alternative titles).
        if writeFields.includes("T") {
            for (index, title) in tune.titles.enumerated() {
                let isFirst = index == 0
                let fontSize = isFirst ? titleFontSize : infoFontSize
                let baselineY = lineHeight * Double(rows.count + 1) - lineHeight * 0.25

                var items: [ResolvedTitleRow.Item] = []

                // Reference number on the first title row, left-aligned.
                if isFirst && writeFields.includes("X") && tune.reference > 0 {
                    items.append(ResolvedTitleRow.Item(
                        text: String(tune.reference),
                        x: leftX, baselineY: baselineY,
                        anchor: .start, fontSize: infoFontSize, isItalic: false))
                }

                items.append(ResolvedTitleRow.Item(
                    text: title.value,
                    x: centerX, baselineY: baselineY,
                    anchor: .middle, fontSize: fontSize, isItalic: !isFirst))

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
            let baselineY = lineHeight * Double(rows.count + 1) - lineHeight * 0.25
            var items: [ResolvedTitleRow.Item] = []

            if line == 0 && !rhythm.isEmpty {
                items.append(ResolvedTitleRow.Item(
                    text: rhythm,
                    x: leftX, baselineY: baselineY,
                    anchor: .start, fontSize: infoFontSize, isItalic: true))
            }

            if line < composers.count {
                items.append(ResolvedTitleRow.Item(
                    text: composers[line],
                    x: rightX, baselineY: baselineY,
                    anchor: .end, fontSize: infoFontSize, isItalic: true))
            }

            rows.append(ResolvedTitleRow(items: items))
        }

        // Tempo row (Q: field).
        if writeFields.includes("Q"), let tempo = tune.tempo {
            let tempoText = tempoAnnotationText(tempo)
            if !tempoText.isEmpty {
                let baselineY = lineHeight * Double(rows.count + 1) - lineHeight * 0.25
                rows.append(ResolvedTitleRow(items: [
                    ResolvedTitleRow.Item(
                        text: tempoText,
                        x: leftX, baselineY: baselineY,
                        anchor: .start, fontSize: infoFontSize, isItalic: false)
                ]))
            }
        }

        guard !rows.isEmpty else { return ([], 0) }
        let totalHeight = lineHeight * Double(rows.count) + layoutConfig.staffSize
        return (rows, totalHeight)
    }
}
