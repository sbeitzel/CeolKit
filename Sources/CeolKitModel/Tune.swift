//
//  Tune.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Tune {
    public let reference: Int                    // X:
    public let titles: [TextString]              // T: (≥0; spec says "should" follow X:)
    public let metadata: TuneMetadata            // C, O, B, D, F, G, H, N, S, R, Z, ...
    public let key: KeySignature                 // K: at end of header — required
    public let meter: Meter                      // M: or default
    public let unitNoteLength: Fraction          // L: or default per §3.1.7
    public let tempo: Tempo?                     // Q:
    public let parts: PartPlan?                  // P:
    public let voices: [Voice]                   // ≥1; single-voice tunes have one synthetic voice
    public let userSymbols: [Character: Decoration]
    public let macros: [MacroDefinition]
    public let directives: [CeolKitDirectiveScope] // see §7
    public let source: SourceRange
}
