import Testing
@testable import CeolKitSVGRenderer

@Suite struct BravuraMetadataTests {

    let metadata: BravuraMetadata

    init() throws {
        metadata = try BravuraMetadata.load()
    }

    @Test func loadsWithoutThrowing() throws {
        _ = try BravuraMetadata.load()
    }

    /// The bundled metadata and `Bravura.otf` are a matched pair; this pins which release
    /// is checked in, so a resource swap that updates only one of them is caught here.
    @Test func bundledMetadataIsBravura1392() {
        #expect(metadata.fontVersion == 1.392)
    }

    /// `engravingDefaults` is not homogeneous — 1.392 added `textFontFamily`, an array of
    /// strings. Decoding must ignore keys it does not consume, whatever their shape, rather
    /// than failing the whole load.
    @Test func nonScalarEngravingDefaultsDoNotBreakLoading() {
        #expect(metadata.engravingDefaults.barlineSeparation > 0)
        #expect(metadata.engravingDefaults.thickBarlineThickness > 0)
    }

    @Test func staffLineThicknessIsPositive() {
        #expect(metadata.engravingDefaults.staffLineThickness > 0)
    }

    @Test func stemThicknessIsPositive() {
        #expect(metadata.engravingDefaults.stemThickness > 0)
    }

    @Test func noteheadBlackBBoxIsNonZero() throws {
        let bbox = try #require(metadata.glyphBBoxes["noteheadBlack"])
        #expect(bbox.width  > 0)
        #expect(bbox.height > 0)
    }

    @Test func noteheadBlackHasStemAnchors() throws {
        let anchors = try #require(metadata.glyphsWithAnchors["noteheadBlack"])
        #expect(anchors["stemUpSE"] != nil)
        #expect(anchors["stemDownNW"] != nil)
    }
}
