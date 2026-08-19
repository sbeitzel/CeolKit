//
//  Tune.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Tune: Sendable {
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
    /// Every `%%score` / `%%staves` that reaches this tune, in source order, each paired
    /// with the stave it governs from — see ``StaffPlanChange``.  Empty when the tune has
    /// no plan at all.
    ///
    /// The plans are also in ``directives``; this is the positional view of them.  Two
    /// changes can share an `effectiveFromStave` — a file-preamble plan and a tune-header
    /// plan both govern from stave 0 — and the later one wins, as it does for every other
    /// directive.
    public let staffPlans: [StaffPlanChange]
    public let source: SourceRange

    public init(
        reference: Int,
        titles: [TextString],
        metadata: TuneMetadata,
        key: KeySignature,
        meter: Meter,
        unitNoteLength: Fraction,
        tempo: Tempo?,
        parts: PartPlan?,
        voices: [Voice],
        userSymbols: [Character: Decoration],
        macros: [MacroDefinition],
        directives: [CeolKitDirectiveScope],
        staffPlans: [StaffPlanChange] = [],
        source: SourceRange
    ) {
        self.reference = reference
        self.titles = titles
        self.metadata = metadata
        self.key = key
        self.meter = meter
        self.unitNoteLength = unitNoteLength
        self.tempo = tempo
        self.parts = parts
        self.voices = voices
        self.userSymbols = userSymbols
        self.macros = macros
        self.directives = directives
        self.staffPlans = staffPlans
        self.source = source
    }
}
