import CeolKitModel

/// Resolves a `TitleFormatSpec` against a `Tune`, producing the concrete text rows
/// that the SVG emitter will lay out.
struct TitleResolver {
    let tune: Tune

    /// One rendered row in the title block.
    struct Row {
        /// At most one item per alignment zone.
        let left: String?
        let center: String?
        let right: String?
    }

    /// Resolves the spec into concrete rows, dropping any box whose every field
    /// value is nil (nothing to display).
    func resolve(_ spec: TitleFormatSpec) -> [Row] {
        spec.boxes.compactMap { resolveBox($0) }
    }

    // MARK: - Private

    private func resolveBox(_ box: TitleFormatSpec.Box) -> Row? {
        var leftParts:   [String] = []
        var centerParts: [String] = []
        var rightParts:  [String] = []

        for entry in box.entries {
            guard let value = fieldValue(for: entry.fieldCode), !value.isEmpty else { continue }

            if entry.concatWithPrevious {
                // Glue this value onto the last item in the same zone.
                switch entry.alignment {
                case .left   where !leftParts.isEmpty:
                    leftParts[leftParts.count - 1] += " " + value
                case .center where !centerParts.isEmpty:
                    centerParts[centerParts.count - 1] += " " + value
                case .right  where !rightParts.isEmpty:
                    rightParts[rightParts.count - 1] += " " + value
                default:
                    // No previous item in this zone — treat as a normal new item.
                    append(value, to: &leftParts, &centerParts, &rightParts, alignment: entry.alignment)
                }
            } else {
                append(value, to: &leftParts, &centerParts, &rightParts, alignment: entry.alignment)
            }
        }

        // Join multiple items in the same zone with a separator (only arises for stacked fields).
        let left   = leftParts.isEmpty   ? nil : leftParts.joined(separator: " / ")
        let center = centerParts.isEmpty ? nil : centerParts.joined(separator: " / ")
        let right  = rightParts.isEmpty  ? nil : rightParts.joined(separator: " / ")

        guard left != nil || center != nil || right != nil else { return nil }
        return Row(left: left, center: center, right: right)
    }

    private func append(
        _ value: String,
        to left: inout [String],
        _ center: inout [String],
        _ right: inout [String],
        alignment: TitleFormatSpec.Alignment
    ) {
        switch alignment {
        case .left:   left.append(value)
        case .center: center.append(value)
        case .right:  right.append(value)
        }
    }

    private func fieldValue(for code: Character) -> String? {
        switch code {
        case "T": return tune.titles.first?.value
        case "R": return tune.metadata.rhythm?.value
        case "C": return tune.metadata.composer?.value
        case "X": return tune.reference > 0 ? String(tune.reference) : nil
        case "O": return tune.metadata.origin.first
        case "A": return tune.metadata.area?.value
        case "B": return tune.metadata.book?.value
        case "N": return tune.metadata.notes?.value
        case "S": return tune.metadata.source?.value
        case "Z": return tune.metadata.transcription?.value
        case "G": return tune.metadata.group?.value
        case "D": return tune.metadata.discography?.value
        default:  return nil
        }
    }
}
