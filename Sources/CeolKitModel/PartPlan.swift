//
//  PartPlan.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// Resolved part play order from the `P:` field (§3.1.9).
/// Complex nested plans (parenthesised repeats) are deferred to v0.2;
/// in v0.1 only simple sequences are fully expanded.
public struct PartPlan {
    public let sequence: [PartLabel]
    public let source: SourceRange
}

public struct PartLabel: Hashable {
    public let letter: Character         // A–Z as written in P:
    public let source: SourceRange
}
