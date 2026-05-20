//
//  Diagnostic.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Diagnostic {
    public enum Severity { case error, warning, info }
    public let severity: Severity
    public let code: DiagnosticCode      // stable identifier, e.g. .invalidPageNumber, .unknownField
    public let message: String           // human-readable
    public let source: SourceRange
    public let related: [SourceRange]    // e.g. earlier definition for a duplicate
    public let hint: String?             // optional fix suggestion
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
}
