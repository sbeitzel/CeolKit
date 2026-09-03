//
//  FooterTagTests.swift
//  CeolKitSVGRendererTests
//
//  Consumer-substitutable footer spans — issue #137.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

private func parse(_ source: String) -> ParseResult {
    CeolKitParser().parse(source, options: .default)
}

private func render(_ footer: String, textRendering: TextRendering = .fontFace) throws -> String {
    let abc = """
    %%footer "\(footer)"
    X:1
    T:Marked
    M:4/4
    L:1/4
    K:C
    CDEF|
    """
    var config = SVGRenderConfig()
    config.textRendering = textRendering
    return try SVGRenderer(config: config).render(parse(abc).score).joined()
}

private let context = FooterContext(pageNumber: 4, pageCount: 9, title: "Reel", date: "1 May")

@Suite("Footer substitution marks (#137)")
struct FooterTagTests {

    // MARK: - Template reading

    @Test func aMarkBecomesItsOwnSegmentCarryingCeolKitsValue() {
        let segments = FooterTemplate.segments(of: "Page ${pagenumber}", context: context)
        #expect(segments == [.literal("Page "), .tag(name: "pagenumber", text: "4")])
    }

    @Test func knownNamesResolveToTheValuesTheOtherPlaceholdersUse() {
        let segments = FooterTemplate.segments(
            of: "${pagenumber}${pagecount}${title}${date}", context: context)
        #expect(segments.map(\.text) == ["4", "9", "Reel", "1 May"])
    }

    @Test func aNameCeolKitHasNoValueForStillMarksTheSpan() {
        let segments = FooterTemplate.segments(of: "${bindername}", context: context)
        // Empty rather than invented: the consumer owns the text, CeolKit only owns the spot.
        #expect(segments == [.tag(name: "bindername", text: "")])
    }

    @Test func placeholdersInsideTheMarkedValuesCannotConjureAMark() {
        // A tune whose title contains ${…} must engrave it, not turn it into a
        // substitution point: marks are read from the raw template, before $T expands.
        let sneaky = FooterContext(pageNumber: 1, pageCount: 1,
                                   title: "${pagenumber}", date: "1 May")
        let segments = FooterTemplate.segments(of: "$T", context: sneaky)
        #expect(segments == [.literal("${pagenumber}")])
    }

    @Test(arguments: ["${1bad}", "${un closed", "${}", "$ {pagenumber}"])
    func textThatIsNotAMarkIsLeftAlone(_ template: String) {
        let segments = FooterTemplate.segments(of: template, context: context)
        #expect(segments == [.literal(template)])
    }

    @Test func columnsSplitAtTabsAndAMarkStaysWhollyInsideOne() {
        let segments = FooterTemplate.segments(of: "a\\t${x}b\\tc", context: context)
        let columns = FooterTemplate.columns(segments)
        #expect(columns.count == 3)
        #expect(columns[0] == [.literal("a")])
        #expect(columns[1] == [.tag(name: "x", text: ""), .literal("b")])
        #expect(columns[2] == [.literal("c")])
    }

    @Test func onlyTheLiteralEndsOfAColumnAreTrimmed() {
        let column = FooterTemplate.trimmed(FooterTemplate.segments(
            of: "   Page ${pagenumber}   ", context: context))
        #expect(column == [.literal("Page "), .tag(name: "pagenumber", text: "4")])
    }

    // MARK: - Emission

    @Test func aMarkedSpanIsWrappedInAFindableSelfDescribingGroup() throws {
        let svg = try render("Page ${pagenumber}")
        #expect(svg.contains("<g id=\"ceolkit-tag-pagenumber\" class=\"ceolkit-tag\""))
        #expect(svg.contains("data-ceolkit-tag=\"pagenumber\""))
        #expect(svg.contains("data-font-size=\"12\""))
        #expect(svg.contains("data-font-family=\"Libertinus Serif\""))
    }

    @Test func theGroupCarriesCeolKitsOwnRenderingOfTheDefaultValue() throws {
        let svg = try render("Page ${pagenumber}")
        // A consumer that ignores the group gets exactly today's output: "Page" beside "1".
        #expect(svg.contains(">Page </text>"))
        #expect(svg.contains(">1</text>"))
    }

    @Test func theSpanIsWrappedInOutlineModeToo() throws {
        // The whole point: `.outlines` leaves no text to rewrite, so the group is the only
        // thing a consumer has to work with — it must be there in every mode.
        let svg = try render("Page ${pagenumber}", textRendering: .outlines)
        #expect(svg.contains("data-ceolkit-tag=\"pagenumber\""))
        #expect(!svg.contains("<text"))
    }

    @Test func aMarkCeolKitCannotFillLeavesAnEmptyGroupAtTheRightSpot() throws {
        let svg = try render("${bindername}", textRendering: .outlines)
        #expect(svg.contains("data-ceolkit-tag=\"bindername\""))
        #expect(svg.contains("data-x=\"306\""))
        #expect(svg.contains("data-text-anchor=\"middle\""))
    }

    @Test func aColumnThatIsNothingButTheMarkKeepsTheColumnsAnchor() throws {
        // A wider replacement then grows leftwards from the right margin instead of off
        // the page.
        let svg = try render("$T\\t\\t${pagenumber}")
        #expect(svg.contains("data-text-anchor=\"end\""))
        #expect(svg.contains("data-x=\"576\""))
    }

    @Test func aMarkMixedWithTextIsPlacedAfterTheTextItFollows() throws {
        let svg = try render("Page ${pagenumber}")
        let literalX = try #require(svg.firstMatch(of: #/<text x="([0-9.]+)"[^>]*>Page /#))
        let tagX = try #require(svg.firstMatch(of: #/data-ceolkit-tag="pagenumber" data-x="([0-9.]+)"/#))
        #expect(Double(tagX.1)! > Double(literalX.1)!)
        // Centred column: the run as a whole still straddles the page centre.
        #expect(Double(literalX.1)! < 306)
    }

    @Test func repeatsOfOneNameGetUniqueIdsAndTheSameTagName() throws {
        let svg = try render("${pagenumber}\\t\\t${pagenumber}")
        #expect(svg.contains("id=\"ceolkit-tag-pagenumber\""))
        #expect(svg.contains("id=\"ceolkit-tag-pagenumber-2\""))
        #expect(svg.ranges(of: "data-ceolkit-tag=\"pagenumber\"").count == 2)
    }

    @Test func anUnmarkedFooterIsUntouched() throws {
        let svg = try render("Page $P")
        #expect(!svg.contains("ceolkit-tag"))
        #expect(svg.contains(">Page 1</text>"))
    }
}
