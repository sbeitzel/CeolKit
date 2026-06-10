/// Parses a raw %%titleformat string into a `TitleFormatSpec`.
///
/// Handles the abcm2ps-compatible syntax only. The abc2svg quoted-string
/// extension (`"..."` with `$`-interpolation) is not supported; quoted text
/// is skipped character by character until the closing `"`.
///
/// Grammar:
///   formatSpec ::= box (',' box)*
///   box        ::= item*
///   item       ::= '+'? letter placement?
///   placement  ::= '0' | '1' | '-' '1'?
///   letter     ::= [A-Z]
struct TitleFormatParser {
    static func parse(_ format: String) -> TitleFormatSpec {
        guard !format.isEmpty else { return .default }

        var boxes: [TitleFormatSpec.Box] = []
        var currentEntries: [TitleFormatSpec.Entry] = []
        var pendingConcat = false
        var i = format.startIndex

        func flushBox() {
            boxes.append(TitleFormatSpec.Box(entries: currentEntries))
            currentEntries = []
            pendingConcat = false
        }

        while i < format.endIndex {
            let ch = format[i]
            format.formIndex(after: &i)

            if ch == "," {
                flushBox()
                continue
            }

            if ch == "+" {
                pendingConcat = true
                continue
            }

            // Skip quoted abc2svg strings
            if ch == "\"" {
                while i < format.endIndex && format[i] != "\"" {
                    format.formIndex(after: &i)
                }
                if i < format.endIndex { format.formIndex(after: &i) }  // consume closing "
                continue
            }

            if ch.isUppercase {
                // Parse the optional placement that may follow immediately
                var alignment: TitleFormatSpec.Alignment = .center
                if i < format.endIndex {
                    let next = format[i]
                    if next == "0" {
                        alignment = .center
                        format.formIndex(after: &i)
                    } else if next == "1" {
                        alignment = .right
                        format.formIndex(after: &i)
                    } else if next == "-" {
                        format.formIndex(after: &i)
                        if i < format.endIndex && format[i] == "1" {
                            format.formIndex(after: &i)
                        }
                        alignment = .left
                    } else if next == "<" {
                        // abc2svg '<' = left
                        alignment = .left
                        format.formIndex(after: &i)
                    } else if next == ">" {
                        // abc2svg '>' = right
                        alignment = .right
                        format.formIndex(after: &i)
                    }
                }
                let entry = TitleFormatSpec.Entry(
                    fieldCode: ch,
                    alignment: alignment,
                    concatWithPrevious: pendingConcat
                )
                currentEntries.append(entry)
                pendingConcat = false
                continue
            }

            // All other characters (spaces, digits not consumed above, etc.) are ignored.
        }

        flushBox()

        // Drop trailing empty boxes produced by a trailing comma or an all-whitespace format.
        let nonEmpty = boxes.filter { !$0.entries.isEmpty }
        return TitleFormatSpec(boxes: nonEmpty)
    }
}
