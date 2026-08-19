//
//  StaffPlanChange.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 8/19/26.
//

import Foundation

/// A `%%score` / `%%staves` plan and the point in the tune it governs from (ABC v2.2 §11.1).
///
/// A plan written in the tune body "resets the music generator, so that voices may appear and
/// disappear for some period of time", which makes it the first directive in CeolKit with
/// *from here on* semantics: every other one flattens to a last-wins scalar for the whole
/// tune.  ``Tune/staffPlans`` is the source-ordered list of those resets.
///
/// The unit is the **stave** — one source line of music, the same unit ``Voice/staves`` is
/// indexed in — because the staves of a system are laid out together, so the plan cannot
/// change part-way through one without splitting it.  A plan written inside a stave is
/// therefore snapped back to the start of the stave enclosing it, with a
/// ``DiagnosticCode/staffPlanSnappedToStave`` diagnostic saying so: snapping is more
/// predictable than an implicit system break the source never asked for.
public struct StaffPlanChange: Hashable, Sendable {
    public let plan: StaffPlan

    /// Index of the stave this plan governs from, inclusive, counted from zero at the start
    /// of the tune body.  A plan written before any music — file preamble or tune header —
    /// is 0.
    public let effectiveFromStave: Int

    /// Where the directive was written, which is not where it takes effect once it snaps.
    public let source: SourceRange

    public init(plan: StaffPlan, effectiveFromStave: Int, source: SourceRange) {
        self.plan = plan
        self.effectiveFromStave = effectiveFromStave
        self.source = source
    }
}
