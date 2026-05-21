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
    // Directive lines (%%name payload) seen in the tune header, preserved for the semantic pass.
    let headerDirectives: [(name: String, payload: String, source: SourceRange)]
    let source: SourceRange
    let missingReferenceNumber: Bool  // true when X: was absent (recovery)
}
