//
//  TunebookTests.swift
//  CeolKitSVGRendererTests
//
//  Created by Stephen Beitzel on 6/13/26.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

class TuneLoader {
    var tunebook: String

    init() throws {
        guard let url = Bundle.module.url(forResource: "tunebook", withExtension: "abc") else {
            throw URLError(.fileDoesNotExist)
        }
        self.tunebook = try String(contentsOf: url, encoding: .utf8)
    }
}

struct TunebookTests {

    // Diagnostic test: kalabakan line 1 has 5 measures (pickup + 4 full).
    // With %%landscape 1 and staffSize=6.0 those must fit on a single system line.
    @Test func kalalabakanFirstLineFitsOnOneSystem() async throws {
        let abc = """
            %abc-2.2
            %%ceolkit:pipeformat true
            %%ceolkit:justifylast true
            %%landscape 1
            X:1
            T:Kalabakan (Borneo)
            R:Reel
            M:C|
            L:1/8
            K:D
            [|: A/ | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 :|]
            """
        let score = CeolKitParser().parse(abc, options: .default).score
        let metadata = try BravuraMetadata.load()
        let effectiveConfig: SVGRenderConfig = {
            var c = SVGRenderConfig()
            for scope in score.tunes.first?.directives ?? [] {
                if case .landscape(true) = scope.directive { c.pageSize = c.pageSize.landscape }
            }
            return c
        }()
        let sizer = MeasureSizer(config: effectiveConfig, metadata: metadata)
        let voice = try #require(score.tunes.first?.voices.first)
        let stave = try #require(voice.staves.first)
        var totalWidth = 0.0
        let unl = score.tunes.first!.unitNoteLength
        for m in stave.measures {
            totalWidth += sizer.size(m, unitNoteLength: unl).naturalWidth
        }
        let usable = effectiveConfig.pageSize.width - effectiveConfig.margins.left - effectiveConfig.margins.right
        let header = systemHeaderWidth(
            clef: voice.properties.clef, keySignature: score.tunes.first?.key, meter: score.tunes.first?.meter,
            metadata: metadata, staffSize: effectiveConfig.staffSize)
        let available = usable - header
        #expect(totalWidth <= available,
                "Total measure width \(totalWidth) should fit in available \(available) (usable=\(usable), header=\(header))")
    }

    @Test func numberOfPages() async throws {
        let loader = try TuneLoader()
        let tunebook = loader.tunebook
        let result = CeolKitParser().parse(tunebook, options: .default)
        let score = result.score
        let renderer = SVGRenderer()
        let pages = try renderer.render(score)

        #expect(pages.count == 15, "Expected to find 15 pages")
    }

    @Test func midTunePageBreaks() async throws {
        let loader = try TuneLoader()
        let tunebook = loader.tunebook
        let result = CeolKitParser().parse(tunebook, options: .default)
        let score = result.score
        let renderer = SVGRenderer()
        let pages = try renderer.render(score)

        let firstPage = try #require(pages.first)

        #expect(firstPage.contains("Bob Cooper of Winnipeg"), "The first tune should be on the first page")
        #expect(!firstPage.contains("Archie Beag"), "The second tune should be put on the second page")

        let tuneNames = ["Bob Cooper of Winnipeg", "Archie Beag", "The Radar Racketeer",
                         "The Parting Glass", "PM Sandy Gordon"]
        var pageAssignments: [String: Int] = [:]
        for (i, page) in pages.enumerated() {
            for name in tuneNames where pageAssignments[name] == nil && page.contains(name) {
                pageAssignments[name] = i + 1
            }
        }

        let archieBeagPage = try #require(pageAssignments["Archie Beag"], "Archie Beag not found")
        let radarPage = try #require(pageAssignments["The Radar Racketeer"], "The Radar Racketeer not found")
        let partingPage = try #require(pageAssignments["The Parting Glass"], "The Parting Glass not found")
        let sandyPage = try #require(pageAssignments["PM Sandy Gordon"], "PM Sandy Gordon not found")

        // Tunes appear in order across pages.
        #expect(archieBeagPage == 2, "Archie Beag should start on page 2 (assignments: \(pageAssignments))")
        #expect(radarPage == 3, "The Radar Racketeer should start on page 3 (assignments: \(pageAssignments))")
        #expect(partingPage == 4, "The Parting Glass should start on page 4 (assignments: \(pageAssignments))")
        #expect(sandyPage == 4, "PM Sandy Gordon should start on page 4 (assignments: \(pageAssignments))")
    }

    @Test func rhythmAndComposerOnSameRowInTitleBlock() async throws {
        let loader = try TuneLoader()
        let tunebook = loader.tunebook
        let result = CeolKitParser().parse(tunebook, options: .default)
        let score = result.score
        let pages = try SVGRenderer().render(score)

        // Page 3 contains The Radar Racketeer (R:Jig, C:Murray Blair & Adrian Melvin).
        // %%writefields TRCQ true is in the preamble, so R should appear in every tune's title block.
        let svg = try #require(pages.first { $0.contains("The Radar Racketeer") })
        #expect(svg.contains(">Jig<"), "Rhythm field 'Jig' should appear as text content in the SVG")

        // Both rhythm and composer must sit on the same baseline (same SVG y value).
        func baselineY(of substring: String, in svg: String) -> Double? {
            for segment in svg.components(separatedBy: "<text ").dropFirst() {
                guard segment.contains(substring) else { continue }
                guard let yRange = segment.range(of: " y=\"") else { continue }
                let after = segment[yRange.upperBound...]
                guard let end = after.firstIndex(of: "\"") else { continue }
                return Double(after[after.startIndex..<end])
            }
            return nil
        }

        // Use "Murray Blair" to avoid worrying about how & is encoded in SVG.
        let rhythmY   = try #require(baselineY(of: "Jig",         in: svg), "No <text> element found for 'Jig'")
        let composerY = try #require(baselineY(of: "Murray Blair", in: svg), "No <text> element found for 'Murray Blair'")
        #expect(rhythmY == composerY,
                "Rhythm 'Jig' (y=\(rhythmY)) and composer (y=\(composerY)) should share the same baseline")
    }
}
