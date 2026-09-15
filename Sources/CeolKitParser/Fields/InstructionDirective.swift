import CeolKitModel
import Foundation

// §3.1.19: "The I: field can be used interchangeably with stylesheet directives so that any
// I:directive may instead be written %%directive, and vice-versa."

/// A stylesheet directive as the parser carries it before interpretation: the `%%name payload`
/// line, or the `I:name payload` field spelling the same thing.
typealias StylesheetDirective = (name: String, payload: String, source: SourceRange)

/// §4.4 instructions that configure the parser rather than the stylesheet.  They are not
/// `%%` directives, so they must not be reported as unsupported ones.
let parserInstructions: Set<String> = [
    "abc-version", "abc-charset", "abc-creator", "abc-include", "linebreak", "decoration",
]

/// The stylesheet directive an `I:` field's text spells, or `nil` when it names one of the
/// ``parserInstructions`` (or nothing at all).
///
/// The name ends at the first space, as it does on a `%%` line, and the payload is whatever
/// follows — already stripped of its comment, with its escapes left for the directive.
func stylesheetDirective(fromInstruction text: TextString) -> StylesheetDirective? {
    let value = text.value.trimmingCharacters(in: .whitespaces)
    let parts = value.split(separator: " ", maxSplits: 1)
    guard let first = parts.first else { return nil }
    let name = String(first)
    guard !parserInstructions.contains(name.lowercased()) else { return nil }
    return (name: name, payload: parts.count > 1 ? String(parts[1]) : "", source: text.source)
}
