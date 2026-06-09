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
}
