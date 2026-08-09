import CeolKitModel
@testable import CeolKitSVGRenderer

/// A renderer pinned to ``TextRendering/fontFace``, for suites that read layout back out of
/// the emitted `<text>` elements.
///
/// Those suites are about *where things landed* — a title's baseline, a mid-line time
/// signature's x, a grace note's spacing — and `<text>` is the most direct probe available:
/// one element per run, carrying its x, y, family, and content as attributes. Outline
/// output states the same facts through `<use transform="translate(…)">`, but reading
/// positions back out of a transform would make those tests as much a test of the parsing
/// helper as of the layout.
///
/// So the mode is pinned rather than the assertions rewritten. That keeps each suite about
/// its own subject, and keeps `.fontFace` exercised end-to-end now that it is no longer the
/// default. Coverage of the default is not lost: both modes are driven by the same
/// `SVGBuilder.text` calls with the same arguments, and `OutlineEmissionTests` asserts on
/// the outline output directly.
func textProbeRenderer(_ config: SVGRenderConfig = SVGRenderConfig()) -> SVGRenderer {
    var pinned = config
    pinned.textRendering = .fontFace
    return SVGRenderer(config: pinned)
}
