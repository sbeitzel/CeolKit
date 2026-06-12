//
//  StyleTests.swift
//  CeolKitParserTests
//
//  Created by Stephen Beitzel on 5/31/26.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

private func parse(_ source: String) -> ParseResult {
    CeolKitParser().parse(source, options: .default)
}

// Same tune as abcTune but with %%ceolkit:justifylast true added.
private let abcTuneJustifyLast = """
%abc-2.2
%%ceolkit:pipeformat true
%%ceolkit:justifylast true
%%titleformat T0, R-1 C1
%%footer "        Generated: $D"
%%straightflags false
%%flatbeams true
%%graceslurs false
%%dateformat "%e %B %Y %H:%M"
%%landscape 1
X:1
T:Kalabakan (Borneo)
R:Reel
C:P/M A. MacDonald
Z:abc-transcription Stephen Beitzel, <sbeitzel@pobox.com>, 2025-11-16
I:linebreak <EOL>
M:C|
L:1/8
Q: 1/4 = 78
K:D
[|: A/ | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 :|]
[| f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}f>e {Gdc}d2 {g}d>f |
{ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
[| A/ | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d>A |
{g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
[| a/ | {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>e{A}e>f {gef}e2 {ag}a2 |
{fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 z |]
"""

private let abcTune = """
%abc-2.2
%%ceolkit:pipeformat true
%%titleformat T0, R-1 C1
%%footer "        Generated: $D"
%%straightflags false
%%flatbeams true
%%graceslurs false
%%dateformat "%e %B %Y %H:%M"
%%landscape 1
X:1
T:Kalabakan (Borneo)
R:Reel
C:P/M A. MacDonald
Z:abc-transcription Stephen Beitzel, <sbeitzel@pobox.com>, 2025-11-16
I:linebreak <EOL>
M:C|
L:1/8
Q: 1/4 = 78
K:D
[|: A/ | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 :|]
[| f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}f>e {Gdc}d2 {g}d>f |
{ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f<e {Gdc}d2 {g}d3/2 |]
[| A/ | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d>A |
{g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
[| a/ | {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>e{A}e>f {gef}e2 a2 |
{fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 z |]
"""

@Suite("Style directives and formatting")
struct StyleTests {

    let result = parse(abcTune)
    var score: Score { result.score }

    @Test func pageIsLandscapeLetter() throws {
        let pages = try SVGRenderer().render(score)
        let svg = try #require(pages.first)
        // US Letter landscape: 792 × 612 points
        #expect(svg.contains("width=\"792\""))
        #expect(svg.contains("height=\"612\""))
    }

    @Test func sevenLinesOfMusicAreRendered() throws {
        let pages = try SVGRenderer().render(score)
        let combined = pages.joined()
        // One treble clef glyph is emitted per system.
        let clefChar = String(SMuFLGlyph.gClef.character)
        let systemCount = combined.components(separatedBy: clefChar).count - 1
        #expect(systemCount == 7)
    }

    @Test func tuneRendersOnOnePage() throws {
        let pages = try SVGRenderer().render(score)
        #expect(pages.count == 1)
    }

    @Test func keySignatureAppearsAtStartOfEveryLine() throws {
        let pages = try SVGRenderer().render(score)
        let combined = pages.joined()
        // D major has 2 sharps (F# and C#); one key signature per system × 7 systems = 14 sharps.
        let sharpChar = String(SMuFLGlyph.accidentalSharp.character)
        let sharpCount = combined.components(separatedBy: sharpChar).count - 1
        #expect(sharpCount == 14)
    }

    @Test func cutTimeAppearsOnFirstLineOnly() throws {
        let pages = try SVGRenderer().render(score)
        let combined = pages.joined()
        let cutTimeChar = String(SMuFLGlyph.timeSigCutCommon.character)
        let cutTimeCount = combined.components(separatedBy: cutTimeChar).count - 1
        #expect(cutTimeCount == 1)
    }

    @Test func repeatDotsAreRendered() throws {
        let pages = try SVGRenderer().render(score)
        let combined = pages.joined()
        let dotChar = String(SMuFLGlyph.repeatDot.character)
        let dotCount = combined.components(separatedBy: dotChar).count - 1
        // The tune has [|: and :|] sections; each produces 2 dots.
        #expect(dotCount >= 2)
    }

    // Regression test for issue #22: SVGRenderer was drawing a spurious bar line
    // between the system header (clef + key sig) and the first note on every
    // non-first system.  The third system ([| A/ …) is the canonical reproducing case.
    @Test func noSpuriousBarLineAtStartOfNonFirstSystems() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig(pageSize: .letter.landscape)

        let tune  = try #require(score.tunes.first)
        let voice = try #require(tune.voices.first)

        let sizer     = MeasureSizer(config: config, metadata: metadata)
        let breaker   = LineBreaker()
        let justifier = Justifier()
        let engine    = VerticalLayoutEngine(config: config, metadata: metadata)

        let usableWidth  = config.pageSize.width - config.margins.left - config.margins.right
        let firstHeaderW = systemHeaderWidth(clef: voice.properties.clef,
                                             keySignature: tune.key,
                                             meter: tune.meter,
                                             metadata: metadata,
                                             staffSize: config.staffSize)
        let laterHeaderW = systemHeaderWidth(clef: voice.properties.clef,
                                             keySignature: tune.key,
                                             meter: nil,
                                             metadata: metadata,
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

        let systems   = breaker.breakIntoSystems(pairs,
                                                  usableWidth: usableWidth,
                                                  firstSystemHeaderWidth: firstHeaderW,
                                                  laterSystemHeaderWidth: laterHeaderW,
                                                  clef: voice.properties.clef,
                                                  keySignature: tune.key,
                                                  meter: tune.meter)
        let widths    = systems.enumerated().map { i, _ in i == 0 ? firstHeaderW : laterHeaderW }
        let justified = justifier.justify(systems,
                                          usableWidth: usableWidth,
                                          justifyLastSystem: config.justifyLastSystem,
                                          systemHeaderWidths: widths)

        let allSystems = engine.layout(justified).pages.flatMap { $0.systems }
        #expect(allSystems.count == 7, "expected 7 systems, got \(allSystems.count)")

        // Systems 1, 2, 4, 6 (0-indexed: 0, 1, 3, 5) start with explicit bar lines in the
        // source ([|: or [|) and must have those bars rendered at the system start.
        #expect(allSystems[0].measures.first?.openingBar?.kind == .sectionRepeatStart)
        for i in [1, 3, 5] {
            #expect(allSystems[i].measures.first?.openingBar?.kind == .start,
                    "system \(i + 1) expected .start opening bar")
        }

        // Systems 3, 5, 7 (0-indexed: 2, 4, 6) are continuation lines — they start with a
        // note and inherit a spurious .single opening bar from the previous system's closing
        // bar.  That bar must be suppressed so nothing is drawn between the clef/key sig and
        // the first note.
        for i in [2, 4, 6] {
            #expect(allSystems[i].measures.first?.openingBar == nil,
                    "system \(i + 1) first measure has spurious opening bar of kind \(String(describing: allSystems[i].measures.first?.openingBar?.kind))")
        }
    }

    // MARK: - %%ceolkit:justifylast

    // Shared layout helper: sizes and breaks measures into justified systems.
    // `justifyLast` is passed explicitly so callers can verify directive-driven behaviour.
    private func justifiedSystems(
        score: Score,
        config: SVGRenderConfig,
        metadata: BravuraMetadata,
        justifyLast: Bool
    ) throws -> (systems: [JustifiedSystem], usableWidth: Double, laterHeaderWidth: Double) {
        let tune  = try #require(score.tunes.first)
        let voice = try #require(tune.voices.first)

        let sizer     = MeasureSizer(config: config, metadata: metadata)
        let breaker   = LineBreaker()
        let justifier = Justifier()

        let usableWidth  = config.pageSize.width - config.margins.left - config.margins.right
        let firstHeaderW = systemHeaderWidth(clef: voice.properties.clef,
                                             keySignature: tune.key,
                                             meter: tune.meter,
                                             metadata: metadata,
                                             staffSize: config.staffSize)
        let laterHeaderW = systemHeaderWidth(clef: voice.properties.clef,
                                             keySignature: tune.key,
                                             meter: nil,
                                             metadata: metadata,
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

        let systems  = breaker.breakIntoSystems(pairs,
                                                 usableWidth: usableWidth,
                                                 firstSystemHeaderWidth: firstHeaderW,
                                                 laterSystemHeaderWidth: laterHeaderW,
                                                 clef: voice.properties.clef,
                                                 keySignature: tune.key,
                                                 meter: tune.meter)
        let widths   = systems.enumerated().map { i, _ in i == 0 ? firstHeaderW : laterHeaderW }
        let justified = justifier.justify(systems,
                                          usableWidth: usableWidth,
                                          justifyLastSystem: justifyLast,
                                          systemHeaderWidths: widths)
        return (justified, usableWidth, laterHeaderW)
    }

    // When %%ceolkit:justifylast true is present the last system must be stretched
    // to fill the full usable line width, just like every other system.
    @Test func lastSystemIsJustifiedWhenDirectiveIsTrue() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig(pageSize: .letter.landscape)
        let score    = parse(abcTuneJustifyLast).score

        // Verify the directive parsed correctly.
        let tune = try #require(score.tunes.first)
        let directiveValue = tune.directives.compactMap { scope -> Bool? in
            if case .justifyLast(let v) = scope.directive { return v }
            return nil
        }.last
        let justifyLast = try #require(directiveValue as Bool?,
            "%%ceolkit:justifylast true should produce a .justifyLast(true) directive on the tune")

        let (systems, usableWidth, laterHeaderW) = try justifiedSystems(
            score: score, config: config, metadata: metadata, justifyLast: justifyLast)

        let lastSystem  = try #require(systems.last)
        let lastTotalW  = lastSystem.measures.reduce(0.0) { $0 + $1.finalWidth }
        let targetWidth = usableWidth - laterHeaderW

        #expect(abs(lastTotalW - targetWidth) < 1.0,
            "last system total width \(lastTotalW) should equal target \(targetWidth) when justifyLast is true")
    }

    // The bottom of the title text block (maximum baseline Y among Libertinus Serif text elements)
    // must be strictly above the topmost rendered music element (minimum Y among all <line>
    // elements, which includes staff lines, stems, bar lines, and ledger lines).
    @Test func titleTextIsAboveHighestNoteStem() throws {
        let pages = try SVGRenderer().render(score)
        let svg   = try #require(pages.first)

        // Collect the Y baseline of every title text element.
        // Title rows use font-family="Libertinus Serif"; Bravura text uses "Bravura".
        // SVGBuilder attribute order: x="..." y="..." font-family="..."
        let titleYValues: [Double] = svg
            .components(separatedBy: "<text ")
            .dropFirst()
            .filter { $0.contains("Libertinus Serif") && !$0.contains("class=\"footer\"") }
            .compactMap { segment -> Double? in
                // Find the y="..." attribute — it follows x="..." in the fixed attribute order.
                guard let yStart = segment.range(of: " y=\"") else { return nil }
                let afterY = segment[yStart.upperBound...]
                guard let yEnd = afterY.firstIndex(of: "\"") else { return nil }
                return Double(afterY[afterY.startIndex..<yEnd])
            }

        // Collect the minimum Y coordinate from every <line> element (both y1 and y2).
        // The smallest value is the topmost rendered music element on the page —
        // either the highest ledger line, the top of a stem, or the top staff line.
        let lineMinY: Double = svg
            .components(separatedBy: "<line ")
            .dropFirst()
            .flatMap { segment -> [Double] in
                var vals: [Double] = []
                for attr in ["y1=\"", "y2=\""] {
                    if let s = segment.range(of: attr) {
                        let after = segment[s.upperBound...]
                        if let e = after.firstIndex(of: "\""), let v = Double(after[after.startIndex..<e]) {
                            vals.append(v)
                        }
                    }
                }
                return vals
            }
            .min() ?? .infinity

        guard !titleYValues.isEmpty else { Issue.record("No Libertinus Serif text elements found in SVG"); return }
        guard lineMinY < .infinity   else { Issue.record("No <line> elements found in SVG"); return }

        let titleMaxY = titleYValues.max()!
        #expect(titleMaxY < lineMinY,
                "Title text bottom (baseline Y=\(titleMaxY)) must be strictly above the topmost music element (Y=\(lineMinY))")
    }

    // Without %%ceolkit:justifylast (or with false) the last system stays at its
    // natural width, noticeably shorter than the full usable line width.
    @Test func lastSystemIsRaggedRightByDefault() throws {
        let metadata = try BravuraMetadata.load()
        let config   = SVGRenderConfig(pageSize: .letter.landscape)
        // abcTune has no %%ceolkit:justifylast directive; default is false.
        let score    = parse(abcTune).score

        let (systems, usableWidth, laterHeaderW) = try justifiedSystems(
            score: score, config: config, metadata: metadata, justifyLast: false)

        let lastSystem  = try #require(systems.last)
        let lastTotalW  = lastSystem.measures.reduce(0.0) { $0 + $1.finalWidth }
        let targetWidth = usableWidth - laterHeaderW

        #expect(lastTotalW < targetWidth - 1.0,
            "last system total width \(lastTotalW) should be less than target \(targetWidth) by default")
    }
}
