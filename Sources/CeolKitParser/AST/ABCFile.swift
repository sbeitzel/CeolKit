import CeolKitModel

struct ABCFile {
    let versionLine: String?
    let filePreamble: [PreambleLine]
    let tunes: [ABCTune]
    let diagnostics: [Diagnostic]
}

struct ABCTune {
    let headerFields: [InformationField]
    // Outer index = logical line; inner = elements on that line.
    // Body-level information fields appear as single-element arrays containing .inlineField.
    let musicBody: [[MusicElement]]
    // Stylesheet directives seen in the tune header, in source order, preserved for the
    // semantic pass: `%%name payload` lines, and `I:name payload` fields, which §3.1.19 makes
    // interchangeable with them.  An `I:` field also stays in `headerFields`.
    let headerDirectives: [StylesheetDirective]
    let source: SourceRange
    // Where the tune starts in the include-expanded line stream; see ``PreambleLine/position``.
    let position: Int
    let missingReferenceNumber: Bool  // true when X: was absent (recovery)
}

/// A line written outside any tune, with where it stands relative to the tunes.
struct PreambleLine {
    let line: LogicalLine
    /// The line's index in the line stream after `I:abc-include` has spliced in the included
    /// files.  This, not `line.source.line`, is what orders preamble lines against tunes: an
    /// included line keeps its own file's line number so that diagnostics point into that
    /// file, and those numbers say nothing about where it stands in the including file
    /// (issue #261).
    let position: Int
}
