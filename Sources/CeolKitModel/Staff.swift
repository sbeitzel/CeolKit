//
//  Staff.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Staff {
    public let measures: [Measure]               // bar-line-delimited
    public let overlays: [VoiceOverlay]          // & overlays per §7.4 of the standard
}
