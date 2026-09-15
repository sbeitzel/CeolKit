import CeolKitModel

struct ABCFile {
    let versionLine: String?
    let filePreamble: [LogicalLine]
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
    let missingReferenceNumber: Bool  // true when X: was absent (recovery)
}
