import CeolKitSVGRenderer
import Foundation
import Testing
#if canImport(CoreText)
import CoreText
#endif

@Suite struct FontRegistrationTests {

    // MARK: - Bundle access (every platform)

    @Test(arguments: CeolKitFonts.Face.allCases)
    func bundledFaceLoads(_ face: CeolKitFonts.Face) throws {
        let url = try CeolKitFonts.url(for: face)
        #expect(url.lastPathComponent == "\(face.rawValue).otf")
        #expect(try !CeolKitFonts.data(for: face).isEmpty)
        #expect(try !CeolKitFonts.base64(for: face).isEmpty)
    }

    /// Bravura must be reachable through the same API as the text faces — a
    /// rasterizer that only learns about Libertinus Serif draws staff lines and
    /// stems but no noteheads, clefs, or rests (issue #33).
    @Test func bravuraIsBundled() throws {
        #expect(CeolKitFonts.Face.allCases.contains(.bravura))
        #expect(CeolKitFonts.Face.bravura.familyName == "Bravura")
    }

    @Test func familyNamesMatchTheEmittedSVG() {
        #expect(CeolKitFonts.Face.libertinusSerifRegular.familyName == "Libertinus Serif")
        #expect(CeolKitFonts.Face.libertinusSerifItalic.familyName == "Libertinus Serif")
        #expect(CeolKitFonts.Face.libertinusSerifItalic.isItalic)
        #expect(!CeolKitFonts.Face.libertinusSerifRegular.isItalic)
    }

    @Test func installWritesEveryFace() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CeolKitFonts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let written = try CeolKitFonts.install(into: directory)

        #expect(written.count == CeolKitFonts.Face.allCases.count)
        for (face, url) in zip(CeolKitFonts.Face.allCases, written) {
            #expect(url.lastPathComponent == "\(face.rawValue).otf")
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(try Data(contentsOf: url) == CeolKitFonts.data(for: face))
        }
    }

    /// Re-installing over an existing directory must succeed rather than fail on
    /// the already-present files.
    @Test func installIsRepeatable() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CeolKitFonts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        try CeolKitFonts.install(into: directory)
        let second = try CeolKitFonts.install(into: directory)

        #expect(second.count == CeolKitFonts.Face.allCases.count)
    }

    // MARK: - Process registration (CoreText platforms only)

    #if canImport(CoreText)
    @Test func registrationSucceedsAndIsIdempotent() {
        #expect(CeolKitFonts.register())
        #expect(CeolKitFonts.register())
    }

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

    /// The regression behind issue #33: Bravura was bundled and embedded in the SVG
    /// but never registered, so native rasterizers had no music font to match.
    ///
    /// Asserts against the resolved font's file URL rather than just its family
    /// name, so the test still means something on a machine that happens to have
    /// its own copy of Bravura installed.
    @Test func bravuraResolvesToTheBundledFace() throws {
        CeolKitFonts.register()
        let font = CTFontCreateWithName("Bravura" as CFString, 12, nil)
        #expect(CTFontCopyFamilyName(font) as String == "Bravura")

        let resolved = try #require(
            CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
            "resolved Bravura has no file URL"
        )
        #expect(resolved.standardizedFileURL == (try CeolKitFonts.url(for: .bravura)).standardizedFileURL)
    }
    #endif
}
