//
//  ScrollSyncAnchorTests.swift
//  CeolKitSVGRendererTests
//
//  End-to-end cover for issue #41: the `ceolkit-meta` scroll-sync anchors (#25)
//  reported "abcLine": 1 for most systems, because `Measure.source` was a
//  fabricated zero range for every measure that did not open its stave.
//

import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
import Foundation
import Testing
@testable import CeolKitSVGRenderer

@Suite("Scroll-sync anchors")
struct ScrollSyncAnchorTests {

    /// Six music lines, three of which open with a barline — the shape that used
    /// to collapse to line 1. Wide enough to keep one system per source line.
    private static let sixLineTune = """
    %abc-2.2
    %%landscape 1
    X:1
    T:Archie Duncan
    R:March
    M:C
    L:1/8
    K:A
    [|: cd | e2 ce a2 ec | d2 Bd f2 dB | e2 ce a2 ec | Bcde f2 ed |
    e2 ce a2 ec | d2 Bd f2 dB | cBAB cdef | e2 A2 A2 :|
    ef | a2 ea c'2 ac' | b2 fb d'2 bd' | a2 ea c'2 ac' | bagf e2 ef |
    [|: a2 ea c'2 ac' | b2 fb d'2 bd' | c'bag fedc | B2 A2 A2 :|
    cBAB cdef | e2 A2 A2 ef | a2 ea c'2 ac' | b2 fb d'2 bd' |
    c'bag fedc | B2 A2 A2 z2 |]
    """

    private func anchorLines(_ abc: String) throws -> [Int] {
        let score = CeolKitParser().parse(abc, options: .default).score
        var config = SVGRenderConfig()
        for scope in score.tunes.first?.directives ?? [] {
            if case .landscape(true) = scope.directive { config.pageSize = config.pageSize.landscape }
        }
        let pages = try SVGRenderer(config: config).render(score)
        return pages.flatMap { page in
            CeolKitMeta.extract(from: page)?.anchors.map(\.abcLine) ?? []
        }
    }

    @Test("Anchors report the source line of the music, not line 1")
    func anchorsFollowSourceLines() throws {
        let lines = try anchorLines(Self.sixLineTune)
        #expect(!lines.isEmpty)
        // The music starts on source line 9; nothing may claim the version line.
        #expect(lines.allSatisfy { $0 >= 9 })
    }

    @Test("Anchors are non-decreasing and cover every music line")
    func anchorsAdvanceThroughTheSource() throws {
        let lines = try anchorLines(Self.sixLineTune)
        #expect(lines == lines.sorted())
        // Each of the six music lines (9…14) is the origin of at least one system.
        #expect(Set(lines) == Set(9...14))
    }

    @Test("A tune whose staves each fit one system anchors one system per line")
    func oneSystemPerSourceLine() throws {
        let abc = """
        X:1
        T:t
        M:C
        L:1/8
        K:C
        CDEF GABc | cBAG FEDC |
        |: CDEF GABc | cBAG FEDC :|
        CDEF GABc | cBAG FEDC |
        """
        #expect(try anchorLines(abc) == [6, 7, 8])
    }
}
