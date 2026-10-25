//
//  TempoBeatGlyphTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #230: a tempo's beat note is drawn in Bravura, so a half or a whole note — which no
//  text face has — renders as a note rather than as missing-glyph boxes.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("A tempo's beat note is drawn in Bravura (#230)")
struct TempoBeatGlyphTests {

    private struct Run {
        let family: String, size: Double, content: String
    }

    /// Every `<text>` run of `abc`, in `fontFace` mode.
    private func runs(_ abc: String) throws -> [Run] {
        var config = SVGRenderConfig()
        config.textRendering = .fontFace
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer(config: config).render(score).joined().matches(
            of: /<text [^>]*?font-family="([^"]+)" font-size="([-0-9.]+)"[^>]*?>([^<]*)<\/text>/
        ).compactMap { m in
            guard let size = Double(m.2) else { return nil }
            return Run(family: String(m.1), size: size, content: String(m.3))
        }
    }

    private func tune(header: String = "", body: String = "C D E F|]") -> String {
        "X:1\nT:Tempo\nM:4/4\nL:1/4\n\(header)K:C\n\(body)\n"
    }

    @Test("Every beat with a note symbol is written in glyphs Bravura has", arguments: [
        (1, 1), (1, 2), (3, 4), (1, 4), (3, 8), (1, 8), (3, 16),
    ])
    func everyBeatIsInBravura(_ numerator: Int, _ denominator: Int) throws {
        let tempo = Tempo(prelude: nil,
                          beats: [Fraction(numerator: numerator, denominator: denominator)],
                          bpm: 88, postlude: nil)
        let text = tempoAnnotationText(tempo)
        #expect(text.hasSuffix(" = 88"))
        let bravura = try OutlineFontSet.font(for: .bravura)
        let music = text.unicodeScalars.filter(TextFace.isSMuFL)
        #expect(!music.isEmpty, "\(text) has no SMuFL note")
        for scalar in music {
            #expect(bravura.glyphID(for: scalar) != nil,
                    "Bravura has no U+\(String(scalar.value, radix: 16, uppercase: true))")
        }
    }

    @Test("A half-note tempo, in the header or the music, draws its note in Bravura")
    func halfNoteTempo() throws {
        let all = try runs(tune(header: "Q:1/2=88\n", body: "C D [Q:1/2=60] E F|]"))
        for bpm in ["88", "60"] {
            let number = try #require(all.firstIndex { $0.content == " = \(bpm)" })
            let note = all[number - 1]
            #expect(note.family == "Bravura")
            #expect(note.content == "\u{ECA3}")
            #expect(note.size == all[number].size)
            #expect(all[number].family == "Libertinus Serif")
        }
    }

    @Test("A dotted beat's dot is Bravura's too, a hair space from the note")
    func dottedBeat() throws {
        let all = try runs(tune(header: "Q:3/8=90\n"))
        let number = try #require(all.firstIndex { $0.content == " = 90" })
        #expect(all[number - 3].content == "\u{ECA5}")
        #expect(all[number - 2].content == "\u{200A}")
        #expect(all[number - 1].content == "\u{ECB7}")
        #expect(all[number - 1].family == "Bravura")
    }

    @Test("Text with no SMuFL character is one run, as it always was")
    func plainTextIsOneRun() {
        let style = TextStyle(size: 12)
        let runs = style.runs(of: "Allegro ♩ = 120")
        #expect(runs.count == 1)
        #expect(runs.first?.text == "Allegro ♩ = 120")
        #expect(runs.first?.style.face == nil)
    }
}
