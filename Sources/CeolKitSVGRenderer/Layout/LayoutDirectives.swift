import CeolKitModel

/// The four layout values a `%%ceolkit:*` directive can move, resolved for one scope level.
///
/// Every one of them is *scoped*: written in the file preamble it governs the document,
/// written in a tune header it governs that tune and no other (ABC v2.2 §4.23).  The
/// renderer therefore resolves it twice — once from the file-global directives, for the
/// document baseline, and once per tune, starting from that baseline — which is the same
/// two-step ``WriteFieldsConfig`` already does for `%%writefields`.  Collecting the four in
/// one value is what keeps the per-tune reset from being four separate `var`s that have to
/// be remembered individually: forgetting one is exactly what issue #153 was.
struct LayoutDirectives {
    /// What `%%ceolkit:pipeformat` asks of the music at this scope.  `.auto` leaves the
    /// choice to the note's staff position, which is the ordinary engraving rule.  A voice's
    /// own `V:` `stem=` outranks it; the emitter resolves the two per staff (issue #74).
    var stemDirection: StemDirection = .auto
    /// Whether the last system of a tune is stretched to the full measure, from
    /// `%%ceolkit:justifylast`.
    var justifyLastSystem: Bool
    /// Multiplier on the staff size, from `%%ceolkit:scale`.  `1.0` = renderer default.
    var scale: Double = 1.0
    /// Step between adjacent grace noteheads, in grace notehead widths, from
    /// `%%ceolkit:gracenotespacing`.
    var graceNoteSpacing: Double

    /// The document baseline before any directive has been read: what the config asks for.
    init(config: SVGRenderConfig) {
        justifyLastSystem = config.justifyLastSystem
        graceNoteSpacing = config.graceNoteSpacing
    }

    mutating func apply(_ directive: CeolKitDirective) {
        switch directive {
        // `false` has to put the direction back, not merely fail to set it: a tune header
        // saying `pipeformat false` under a preamble saying `true` is asking for the
        // ordinary pitch rule, and nothing else in the tune can ask for it.
        case .pipeFormat(let on):         stemDirection = on ? .down : .auto
        case .justifyLast(let on):        justifyLastSystem = on
        case .scale(let factor):          scale = factor
        case .graceNoteSpacing(let step): graceNoteSpacing = step
        default: break
        }
    }

    /// This baseline with `tune`'s own directives layered on top.
    ///
    /// Every directive the tune carries is applied, file-global ones included: the parser
    /// folds the preamble into the first tune's list ahead of that tune's own entries, so
    /// re-applying them here lands on the value they already put in the baseline, and every
    /// later tune carries none of them at all.  ``WriteFieldsConfig`` is layered the same way.
    func layering(_ tune: Tune) -> LayoutDirectives {
        var resolved = self
        for scope in tune.directives { resolved.apply(scope.directive) }
        return resolved
    }
}
