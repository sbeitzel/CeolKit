//
//  LineBreakBalanceTests.swift
//  CeolKitSVGRendererTests
//
//  End-to-end cover for issue #40: a source line that has to be split across systems must
//  not leave a lone measure behind for the justifier to smear across the page.
//

import CeolKitModel
import CeolKitParser
import Foundation
import Testing
@testable import CeolKitSVGRenderer

// A pipe reel whose source lines run to eight bars — long enough that every one of them has
// to be broken across two systems on a landscape page.
private let splitLineTune = """
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
[| f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}f>e {Gdc}d2 {g}d>f |
{ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
[| A/ | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d>A |
{g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
"""

@Suite("Line-break balancing")
struct LineBreakBalanceTests {

    /// Runs passes 1–3 over the tune's first voice, the way `SVGRenderer` does.
    private func layOut(_ abc: String, config: SVGRenderConfig)
    throws -> (systems: [System], justified: [JustifiedSystem], targets: [Double]) {
        let metadata = try BravuraMetadata.load()
        let score = CeolKitParser().parse(abc, options: .default).score
        let tune  = try #require(score.tunes.first)
        let voice = try #require(tune.voices.first)

        let sizer     = MeasureSizer(config: config, metadata: metadata)
        let breaker   = LineBreaker(overflowTolerance: config.lineOverflowTolerance)
        let justifier = Justifier(maxStretch: config.maxSystemStretch)

        let usableWidth  = config.pageSize.width - config.margins.left - config.margins.right
        let firstHeaderW = systemHeaderWidth(clef: voice.properties.clef, keySignature: tune.key,
                                             meter: tune.meter, metadata: metadata,
                                             staffSize: config.staffSize)
        let laterHeaderW = systemHeaderWidth(clef: voice.properties.clef, keySignature: tune.key,
                                             meter: nil, metadata: metadata,
                                             staffSize: config.staffSize)

        var pairs: [(measure: SizedMeasure, breakAfter: ScoreLineBreak?)] = []
        for (si, stave) in voice.staves.enumerated() {
            let isLast = si == voice.staves.count - 1
            for (mi, m) in stave.measures.enumerated() {
                pairs.append((
                    measure: sizer.size(m, unitNoteLength: tune.unitNoteLength),
                    breakAfter: (!isLast && mi == stave.measures.count - 1) ? .hard : nil
                ))
            }
        }

        let systems = breaker.breakIntoSystems(pairs, usableWidth: usableWidth,
                                               firstSystemHeaderWidth: firstHeaderW,
                                               laterSystemHeaderWidth: laterHeaderW,
                                               clef: voice.properties.clef,
                                               keySignature: tune.key,
                                               meter: tune.meter)
        let headerWidths = systems.enumerated().map { i, _ in i == 0 ? firstHeaderW : laterHeaderW }
        let justified = justifier.justify(systems, usableWidth: usableWidth,
                                          justifyLastSystem: true,
                                          systemHeaderWidths: headerWidths)
        let targets = headerWidths.map { usableWidth - $0 }
        return (systems, justified, targets)
    }

    // The reported symptom: a system stretched to ~3.6× its natural note spacing.
    @Test func noSystemIsStretchedPastTheCap() throws {
        let config = SVGRenderConfig(pageSize: .letter.landscape)
        let (_, justified, _) = try layOut(splitLineTune, config: config)

        for (i, system) in justified.enumerated() {
            let natural = system.measures.reduce(0.0) { $0 + $1.source.naturalWidth }
            let final   = system.measures.reduce(0.0) { $0 + $1.finalWidth }
            guard natural > 0 else { continue }
            #expect(final / natural <= config.maxSystemStretch + 1e-9,
                    "system \(i) stretched \(final / natural)× — past the \(config.maxSystemStretch)× cap")
        }
    }

    // The cause: a split stave whose last system holds a single orphaned measure.  Every one
    // of these staves is eight bars over two systems, so neither half may be a lone bar.
    @Test func splitStavesDoNotOrphanASingleMeasure() throws {
        let config = SVGRenderConfig(pageSize: .letter.landscape)
        let (systems, _, _) = try layOut(splitLineTune, config: config)

        let split = systems.filter(\.staveWasSplit)
        #expect(!split.isEmpty, "the fixture must actually exercise a split stave")
        for (i, system) in split.enumerated() {
            #expect(system.measures.count > 1,
                    "system \(i) of a split stave holds a single orphaned measure")
        }
    }

    // Music never crosses the right margin, whether the justifier stretched it, compressed a
    // tolerated overrun, or left it short at the cap.
    @Test func noSystemOverrunsItsLine() throws {
        let config = SVGRenderConfig(pageSize: .letter.landscape)
        let (_, justified, targets) = try layOut(splitLineTune, config: config)

        for (i, system) in justified.enumerated() {
            let final = system.measures.reduce(0.0) { $0 + $1.finalWidth }
            #expect(final <= targets[i] + 1e-6,
                    "system \(i) is \(final) pt wide on a \(targets[i]) pt line")
        }
    }
}
