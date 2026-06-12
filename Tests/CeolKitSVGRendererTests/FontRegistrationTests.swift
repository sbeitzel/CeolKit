#if canImport(CoreText)
import CoreText
import CeolKitSVGRenderer
import Testing

@Suite struct FontRegistrationTests {

    @Test func registeredFamilyResolvesByName() {
        CeolKitFonts.register()
        let descriptor = CTFontDescriptorCreateWithNameAndSize("Libertinus Serif" as CFString, 12)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        let family = CTFontCopyFamilyName(font) as String
        #expect(family == "Libertinus Serif")
    }

    @Test func italicFaceIsRegistered() {
        CeolKitFonts.register()
        let font = CTFontCreateWithName("LibertinusSerif-Italic" as CFString, 12, nil)
        let traits = CTFontGetSymbolicTraits(font)
        #expect(CTFontCopyFamilyName(font) as String == "Libertinus Serif")
        #expect(traits.contains(.traitItalic))
    }
}
#endif
