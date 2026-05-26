//
//  VoiceOverlay.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// A secondary voice overlaid on the same staff via `&` (§7.4).
/// Full voice overlay support is deferred to v0.2.
public struct VoiceOverlay: Sendable {
    public let measures: [Measure]
    public let source: SourceRange

    public init(measures: [Measure], source: SourceRange) {
        self.measures = measures
        self.source = source
    }
}
