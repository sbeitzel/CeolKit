import Foundation
import Testing
@testable import CeolKitSVGRenderer

/// Checks `SMuFLGlyph` against SMuFL's own published `glyphnames.json`.
///
/// The hazard being guarded here is quiet: a mistyped Private Use Area codepoint neither
/// crashes nor renders nothing — it engraves whatever other symbol happens to live at that
/// address.  Proofreading a table of hex literals catches that about as reliably as you would
/// expect, so the specification's machine-readable table does it instead.
///
/// The table is checked in rather than fetched; see `Resources/glyphnames-PROVENANCE.txt`.
@Suite("SMuFL glyph name and codepoint conformance")
struct SMuFLGlyphConformanceTests {

    /// One entry of `glyphnames.json`.  Only `codepoint` is needed; `description` and
    /// `alternateCodepoint` are present in the file but nothing here asserts on them.
    private struct GlyphNameEntry: Decodable {
        let codepoint: String
    }

    /// Canonical glyph name → codepoint, as published by the W3C Music Notation Community Group.
    private let published: [String: UInt32]

    init() throws {
        let url = try #require(
            Bundle.module.url(forResource: "glyphnames", withExtension: "json"),
            "glyphnames.json is missing from the test bundle — check Package.swift resources"
        )
        let raw = try JSONDecoder().decode([String: GlyphNameEntry].self,
                                           from: try Data(contentsOf: url))
        published = raw.compactMapValues { Self.parseCodepoint($0.codepoint) }
    }

    /// `"U+E0A4"` → `0xE0A4`.  Returns `nil` for anything not in that form, which the
    /// sanity check below turns into a failure rather than a silently skipped glyph.
    private static func parseCodepoint(_ text: String) -> UInt32? {
        guard text.hasPrefix("U+") else { return nil }
        return UInt32(text.dropFirst(2), radix: 16)
    }

    /// `0xE0A4` → `"U+E0A4"`, so a failure message reads the way the specification does.
    private static func hex(_ codepoint: UInt32) -> String {
        "U+" + String(codepoint, radix: 16, uppercase: true)
    }

    /// If the oracle itself fails to load, every other test in this suite passes vacuously.
    @Test("The published table loads and covers the whole specification")
    func publishedTableLoads() {
        // SMuFL 1.4 defines 2,940 recommended glyphs.  An exact count would fail on any
        // future append, which is not what this test is for; a floor catches a truncated
        // or half-parsed file.
        #expect(published.count > 2900)
        #expect(published["noteheadBlack"] == 0xE0A4)
    }

    @Test("Every SMuFLGlyph case names a glyph the specification defines")
    func everyCaseIsACanonicalName() {
        for glyph in SMuFLGlyph.allCases {
            #expect(published[glyph.rawValue] != nil,
                    "\(glyph.rawValue) is not a canonical SMuFL glyph name")
        }
    }

    @Test("Every SMuFLGlyph case carries the specification's codepoint")
    func everyCodepointMatchesTheSpecification() {
        for glyph in SMuFLGlyph.allCases {
            guard let expected = published[glyph.rawValue] else { continue } // reported above
            let actual = glyph.unicodeScalar.value
            #expect(actual == expected,
                    "\(glyph.rawValue): CeolKit has \(Self.hex(actual)), SMuFL says \(Self.hex(expected))")
        }
    }

    /// Two cases sharing a codepoint means one of them draws the wrong symbol, and the
    /// per-glyph check above cannot see it — both would agree with the table if the *name*
    /// were the thing that was mistyped.
    @Test("No two cases resolve to the same codepoint")
    func codepointsAreDistinct() {
        var seen: [UInt32: SMuFLGlyph] = [:]
        for glyph in SMuFLGlyph.allCases {
            let codepoint = glyph.unicodeScalar.value
            if let other = seen[codepoint] {
                Issue.record("\(glyph.rawValue) and \(other.rawValue) both map to \(Self.hex(codepoint))")
            }
            seen[codepoint] = glyph
        }
    }

    /// Every glyph the renderer can ask for must actually exist in the face that is bundled
    /// to draw it.  `glyphnames.json` says what the symbol *is*; only Bravura's own metadata
    /// says whether this package can render it.
    @Test("Every SMuFLGlyph case is present in the bundled Bravura")
    func everyGlyphExistsInBravura() throws {
        let metadata = try BravuraMetadata.load()
        for glyph in SMuFLGlyph.allCases {
            #expect(metadata.glyphBBoxes[glyph.rawValue] != nil,
                    "\(glyph.rawValue) has no bounding box in the bundled Bravura metadata")
        }
    }
}
