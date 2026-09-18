//
//  Score.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Score: Sendable {
    public let source: SourceRange
    public let dialect: Dialect
    public let creator: String?                  // I:abc-creator
    public let charset: String?                  // I:abc-charset
    /// The `%%footer` template written in the file header, or `nil` where the file header
    /// states none.
    ///
    /// A directive in the file header governs the whole file (ABC v2.2 §4.23), so this is the
    /// footer every tune starts from — not the document's only one.  A tune whose own header
    /// names a footer carries it in ``Tune/footer`` and prints that instead (issue #155).
    public let footer: String?
    public let tunes: [Tune]
    public let freeText: [TextBlock]
    public let typesetText: [TypesetText]
    public let diagnostics: [Diagnostic]         // all issues from all stages

    public init(source: SourceRange, dialect: Dialect, creator: String?, charset: String?,
                footer: String? = nil, tunes: [Tune],
                freeText: [TextBlock], typesetText: [TypesetText], diagnostics: [Diagnostic]) {
        self.source = source
        self.dialect = dialect
        self.creator = creator
        self.charset = charset
        self.footer = footer
        self.tunes = tunes
        self.freeText = freeText
        self.typesetText = typesetText
        self.diagnostics = diagnostics
    }
}
