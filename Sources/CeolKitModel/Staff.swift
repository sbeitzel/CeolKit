//
//  Staff.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Staff: Sendable {
    public let measures: [Measure]               // bar-line-delimited
    /// The `&` overlays written on this stave (§7.4), outermost layer first.
    ///
    /// Every stave of one voice carries the same number of overlays, and every overlay holds
    /// exactly as many measures as ``measures`` — see ``VoiceOverlay``.  A voice the body
    /// never wrote an `&` in has none at all.
    public let overlays: [VoiceOverlay]

    public init(measures: [Measure], overlays: [VoiceOverlay]) {
        self.measures = measures
        self.overlays = overlays
    }
}
