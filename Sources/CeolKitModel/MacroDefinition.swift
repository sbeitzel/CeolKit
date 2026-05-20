//
//  MacroDefinition.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// A macro definition from an `m:` field.
/// Full macro expansion is deferred to v0.2; pattern and expansion are stored
/// verbatim so the semantic pass can skip them without losing information.
public struct MacroDefinition {
    public let pattern: String           // left-hand side (e.g. `~G2`)
    public let expansion: String         // right-hand side (e.g. `{A}G2`)
    public let source: SourceRange
}
