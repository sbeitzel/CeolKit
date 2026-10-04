//
//  AnnotationSpacingTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #185: note spacing ignored the width of chord symbols and annotations, so text
//  wider than its note's column printed over the next note's.
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

@Suite("Text on notes is spaced so it does not collide (#185)")
struct AnnotationSpacingTests {

    // MARK: - Sources and probes

    private func tune(_ body: String, meter: String = "4/4") -> String {
        ["X:1", "T:Spacing", "M:\(meter)", "L:1/4", "K:C", body].joined(separator: "\n") + "\n"
    }

    private func layout(_ abc: String) throws -> ResolvedLayout {
        let score = CeolKitParser().parse(abc, options: .default).score
        return try SVGRenderer().renderDocument(score).layout
    }

    private let staffSize = SVGRenderConfig().scaledStaffSize
    private var fontSize: Double { AnnotationBand.fontSize(staffSize: staffSize) }

    /// Each note of `system` that carries text in a band, with where it starts and how wide
    /// its widest line there is.
    private func texts(in system: ResolvedSystem, below: Bool = false) throws
        -> [(x: Double, width: Double)] {
        let metadata = try BravuraMetadata.load()
        let style = TextStyle(size: fontSize)
        return system.measures.flatMap(\.events).compactMap { event in
            let (chordSymbol, annotations): (ChordSymbol?, [Annotation])
            switch event.kind {
            case .note(let n):  (chordSymbol, annotations) = (n.chordSymbol, n.annotations)
            case .chord(let c): (chordSymbol, annotations) = (c.chordSymbol, c.annotations)
            default:            return nil
            }
            let lines: [AnnotationBand.Line] = below
                ? AnnotationBand.linesBelow(annotations: annotations).map { [.text($0)] }
                : AnnotationBand.linesAbove(chordSymbol: chordSymbol, annotations: annotations)
            guard !lines.isEmpty else { return nil }
            let width = lines.map {
                AnnotationBand.width(of: $0, style: style, metadata: metadata)
            }.max() ?? 0
            return (event.origin.x, width)
        }
    }

    /// Fails wherever one note's text reaches the next's, bar lines included.
    private func expectNoOverlap(_ layout: ResolvedLayout, below: Bool = false,
                                 sourceLocation: SourceLocation = #_sourceLocation) throws {
        for system in layout.pages.flatMap(\.systems) {
            let runs = try texts(in: system, below: below)
            for (a, b) in zip(runs, runs.dropFirst()) {
                #expect(a.x + a.width < b.x,
                        "text at \(a.x) runs \(a.width) wide into text at \(b.x)",
                        sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: - The reproduction

    @Test("The issue's chords no longer touch, within a bar or across one")
    func reproductionDoesNotOverlap() throws {
        let abc = tune(#""Bb"B "F#m"A "C#"c "Eb7"e | "G♭"G "F♯"F "Bbmaj7/D"D "Am"A |]"#)
        try expectNoOverlap(try layout(abc))
    }

    @Test("Annotations above and below the staff are spaced the same way")
    func annotationsDoNotOverlap() throws {
        let abc = tune(#""^a long annotation"C "^another"D "_underneath here"E "_and here"F |]"#)
        let laid = try layout(abc)
        try expectNoOverlap(laid)
        try expectNoOverlap(laid, below: true)
    }

    @Test("Chord-line text that is not a chord is measured too")
    func chordLineTextIsMeasured() throws {
        try expectNoOverlap(try layout(tune(#""repeat of part two"C "Fine"D E F |]"#)))
    }

    @Test("Room for a chord is shared over the notes between, not put before the next")
    func roomIsShared() throws {
        let abc = tune(#""Bbmaj7(#11)/D"C/2 D/2 E/2 F/2 "Am"G2 |]"#)
        let laid = try layout(abc)
        try expectNoOverlap(laid)
        let system = try #require(laid.pages.first?.systems.first)
        let xs = system.measures[0].events.filter {
            if case .note = $0.kind { return true }
            return false
        }.map(\.origin.x)
        let gaps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        // The chord needed more than the four eighths gave it…
        let bare = try #require(try layout(tune("C/2 D/2 E/2 F/2 G2 |]"))
                                    .pages.first?.systems.first)
        let bareXs = bare.measures[0].events.filter {
            if case .note = $0.kind { return true }
            return false
        }.map(\.origin.x)
        #expect(xs[4] - xs[0] > bareXs[4] - bareXs[0])
        // …and the eighths are still evenly spaced.
        let eighths = Array(gaps.prefix(4))
        #expect((eighths.max() ?? 0) - (eighths.min() ?? 0) < 0.01, "\(gaps)")
    }

    // MARK: - Beside the notehead

    @Test("\">text\" clears the next note")
    func rightTextClearsTheNextNote() throws {
        let system = try #require(try layout(tune(#"">to the right"E F G A |]"#))
                                    .pages.first?.systems.first)
        let events = system.measures[0].events
        let right = AnnotationBand.width(of: "to the right", font: OutlineFontSet.textFace(),
                                         fontSize: fontSize)
        #expect(events[0].origin.x + right < events[1].origin.x)
    }

    @Test("\"<text\" on a bar's first note clears the bar line")
    func leftTextClearsTheBarLine() throws {
        let system = try #require(try layout(tune(#"C D E F | "<to the left"G A B c |]"#))
                                    .pages.first?.systems.first)
        let bar = system.measures[1]
        let left = AnnotationBand.width(of: "to the left", font: OutlineFontSet.textFace(),
                                        fontSize: fontSize)
        #expect(bar.events[0].origin.x - left > bar.origin.x)
    }

    // MARK: - Line breaking and stretching

    @Test("A line full of long chords wraps where the bare notes would not")
    func chordsWidenTheNaturalWidth() throws {
        let bars = Array(repeating: "C D E F", count: 6).joined(separator: " | ") + " |]"
        let chorded = Array(repeating: #""Cmaj7/G"C "Dm7b5"D "Ebdim7"E "F#m7"F"#, count: 6)
            .joined(separator: " | ") + " |]"
        let bare = try layout(tune(bars)).pages.flatMap(\.systems).count
        let withChords = try layout(tune(chorded))
        #expect(withChords.pages.flatMap(\.systems).count > bare)
        try expectNoOverlap(withChords)
    }

    @Test("A bar with no text is sized exactly as before")
    func textFreeBarIsUntouched() throws {
        let metadata = try BravuraMetadata.load()
        let sizer = MeasureSizer(config: SVGRenderConfig(), metadata: metadata)
        let score = CeolKitParser().parse(tune("C D/2 E/2 F G |]"), options: .default).score
        let measure = try #require(score.tunes.first?.voices.first?.staves.first?.measures.first)
        let sized = sizer.size(measure)
        #expect(sized.musicOffsets == sized.eventOffsets)
        #expect(sized.musicWidth == sized.naturalWidth)
    }

    // MARK: - The stretch

    @Test("floorScale stretches the music and holds each gap to its floor")
    func floorScaleSolves() {
        // Three gaps of music 10; the middle one was widened to 40.  Filling 90 stretches
        // the outer two to 25 each and leaves the middle at its floor.
        let k = Justifier.floorScale(music: [10, 10, 10], floors: [10, 40, 10], target: 90)
        #expect(abs(k - 2.5) < 1e-9)
        // Past the point the middle gap's music catches up, all three stretch together.
        let wide = Justifier.floorScale(music: [10, 10, 10], floors: [10, 40, 10], target: 150)
        #expect(abs(wide - 5) < 1e-9)
        // With no floors above the music it is plain proportional stretching.
        let plain = Justifier.floorScale(music: [10, 20], floors: [10, 20], target: 60)
        #expect(abs(plain - 2) < 1e-9)
    }
}
