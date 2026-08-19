//
//  Diagnostic.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Diagnostic: Sendable {
    public enum Severity: Sendable { case error, warning, info }
    public let severity: Severity
    public let code: DiagnosticCode      // stable identifier, e.g. .invalidPageNumber, .unknownField
    public let message: String           // human-readable
    public let source: SourceRange
    public let related: [SourceRange]    // e.g. earlier definition for a duplicate
    public let hint: String?             // optional fix suggestion

    public init(
        severity: Severity,
        code: DiagnosticCode,
        message: String,
        source: SourceRange,
        related: [SourceRange] = [],
        hint: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.source = source
        self.related = related
        self.hint = hint
    }
}

public enum DiagnosticCode: String, Codable, Sendable {
    // Music syntax
    case constructOutOfOrder
    case reservedCharacter
    case danglingTie
    /// Two voices of the same tune disagree about how much music a source line holds,
    /// so the staves of a system cannot be aligned from the source alone.  The renderer
    /// pads the short voice with invisible full-measure rests and carries on.
    case voiceLengthMismatch
    // Fields
    case unknownField
    case malformedFieldPayload
    case missingRequiredField
    // CeolKit extensions
    case invalidPageNumber
    case misplacedStemAlignment
    case invalidScale
    case invalidGraceNoteSpacing
    // Directives
    case unknownDirective
    case redundantDirective
    /// A `%%score` / `%%staves` payload did not parse (ABC v2.2 §11.1).  The whole
    /// directive is dropped rather than stored as a partial tree.
    case invalidStaffPlan
    /// A `%%score` / `%%staves` was written part-way through a stave, where the plan cannot
    /// change without splitting the system.  It takes effect from the start of the stave
    /// enclosing it instead — see `StaffPlanChange`.
    case staffPlanSnappedToStave
    // Field keys
    case unknownKey
    // Include directive
    case includeNoBaseDirectory
    case includeFileNotFound
    case circularInclude
    case includeIgnoredInline
    case usingDefaultFileResolver
}
