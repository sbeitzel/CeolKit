#if canImport(CoreText)
import CoreText
import Foundation

/// Registers the fonts bundled with CeolKitSVGRenderer with the current process.
///
/// The emitted SVG embeds Libertinus Serif via `@font-face` data URIs, which
/// browser-based consumers honor. Native rasterizers (e.g. SVGKit, which resolves
/// `font-family` through CoreText/NSFontManager) ignore `@font-face` and can only
/// match fonts already known to the process. Call ``register()`` once at startup
/// so "Libertinus Serif" (regular and italic) resolves by family name.
public enum CeolKitFonts {

    /// Registers Libertinus Serif Regular and Italic with process scope.
    /// Idempotent and thread-safe; calls after the first are no-ops.
    public static func register() {
        _ = registration
    }

    private static let registration: Void = {
        let urls = ["LibertinusSerif-Regular", "LibertinusSerif-Italic"].compactMap {
            Bundle.module.url(forResource: $0, withExtension: "otf")
        }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }()
}
#endif
