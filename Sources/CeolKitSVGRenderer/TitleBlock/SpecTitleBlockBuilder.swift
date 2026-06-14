import CeolKitModel

/// Builds a title block following the ABC v2.2 §6.1.3 typesetting rules.
///
/// Layout (top to bottom):
///   - First T: field — centered, large font; X: reference left-aligned on the same row if enabled
///   - Additional T: fields — centered, small italic (alternative titles)
///   - Rhythm/Composer row: R: left-aligned, first C: right-aligned with O: appended in parens
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

        // Rhythm / Composer row.
        let includeR = writeFields.includes("R")
        let includeC = writeFields.includes("C")

        if includeR || includeC {
            let baselineY = lineHeight * Double(rows.count + 1) - lineHeight * 0.25
            var items: [ResolvedTitleRow.Item] = []

            if includeR, let rhythm = tune.metadata.rhythm?.value, !rhythm.isEmpty {
                items.append(ResolvedTitleRow.Item(
                    text: rhythm,
                    x: leftX, baselineY: baselineY,
                    anchor: .start, fontSize: infoFontSize, isItalic: true))
            }

            if includeC, let composer = tune.metadata.composer?.value, !composer.isEmpty {
                var composerText = composer
                if writeFields.includes("O"),
                   let origin = tune.metadata.origin.first, !origin.isEmpty {
                    composerText += " (\(origin))"
                }
                items.append(ResolvedTitleRow.Item(
                    text: composerText,
                    x: rightX, baselineY: baselineY,
                    anchor: .end, fontSize: infoFontSize, isItalic: true))
            }

            if !items.isEmpty {
                rows.append(ResolvedTitleRow(items: items))
            }
        }

        guard !rows.isEmpty else { return ([], 0) }
        let totalHeight = lineHeight * Double(rows.count) + layoutConfig.staffSize
        return (rows, totalHeight)
    }
}
