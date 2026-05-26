import Testing
@testable import CeolKitSVGRenderer

@Suite struct ConfigTests {

    @Test func pageSizeA4HasCorrectDimensions() {
        #expect(PageSize.a4.width  == 595.28)
        #expect(PageSize.a4.height == 841.89)
    }

    @Test func letterLandscapeSwapsWidthAndHeight() {
        let landscape = PageSize.letter.landscape
        #expect(landscape.width  == PageSize.letter.height)
        #expect(landscape.height == PageSize.letter.width)
    }

    @Test func defaultConfigInitializesWithoutCrashing() {
        let cfg = SVGRenderConfig()
        #expect(cfg.staffSize > 0)
        #expect(cfg.systemGap > 0)
    }

    @Test func defaultSystemGapIsEightStaffSizes() {
        let cfg = SVGRenderConfig()
        #expect(cfg.systemGap == cfg.staffSize * 8)
    }

    @Test func customSystemGapIsRespected() {
        let cfg = SVGRenderConfig(systemGap: 42.0)
        #expect(cfg.systemGap == 42.0)
    }
}
