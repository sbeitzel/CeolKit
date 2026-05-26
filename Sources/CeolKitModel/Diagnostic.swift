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
    // Fields
    case unknownField
    case malformedFieldPayload
    case missingRequiredField
    // CeolKit extensions
    case invalidPageNumber
    case misplacedStemAlignment
    // Directives
    case unknownDirective
    // Field keys
    case unknownKey
}
