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
