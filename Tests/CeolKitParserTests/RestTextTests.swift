//
//  RestTextTests.swift
//  CeolKitParserTests
//
//  Issue #299: a chord symbol (ABC v2.2 §4.18) or annotation (§4.19) written before a rest
//  belongs to the rest.  `Rest` had nowhere to keep one, so it stayed pending: replaced by
//  the next one written, or drawn on the next note.
//

import Testing
import CeolKitModel
import CeolKitParser

@Suite("Chord symbols and annotations on rests (§4.18–4.19)")
struct RestTextTests {

    private func events(_ body: String) -> [Event] {
        let abc = "X:1\nT:Test\nM:4/4\nL:1/4\nK:C\n\(body)\n"
        let written = parse(abc).score.firstTune?.singleVoiceMeasures.flatMap(\.events) ?? []
        // A tuplet's own events, in its place.
        return written.flatMap { event -> [Event] in
            if case .tuplet(let t) = event { t.events } else { [event] }
        }
    }

    private func rests(_ body: String) -> [Rest] {
        events(body).compactMap { if case .rest(let r) = $0 { r } else { nil } }
    }

    private func notes(_ body: String) -> [Note] {
        events(body).compactMap { if case .note(let n) = $0 { n } else { nil } }
    }

    @Test("Every kind of rest keeps the chord symbol written before it")
    func everyKindOfRest() {
        let found = rests(#""Am"z4 | "G"Z | "C"Z2 | "D"x4 | "E"X | "F"z C3 |]"#)
        #expect(found.map(\.kind) == [.normal, .fullMeasure, .fullMeasure, .invisible,
                                      .fullMeasureInvisible, .normal])
        #expect(found.map { $0.chordSymbol?.raw } == ["Am", "G", "C", "D", "E", "F"])
    }

    @Test("A chord symbol on a rest is not carried on to the next note")
    func doesNotLeakOntoTheNextNote() {
        let after = notes(#""E"z C3 |]"#)
        #expect(after.count == 1)
        #expect(after.first?.chordSymbol == nil)
    }

    @Test("A rest keeps its annotations, in every position")
    func annotations() throws {
        let rest = try #require(rests(#""^above" "_below" "<left" ">right" "@1,2 at"z C3 |]"#).first)
        #expect(rest.annotations.map(\.text.value) == ["above", "below", "left", "right", "at"])
        #expect(rest.annotations.first?.position == .above)
        #expect(rest.annotations.dropFirst().first?.position == .below)
        let note = try #require(notes(#""^above"z C3 |]"#).first)
        #expect(note.annotations.isEmpty)
    }

    @Test("A rest in a tuplet keeps its text")
    func inATuplet() throws {
        let rest = try #require(rests(#"(3"Am""^x"zCD C2 |]"#).first)
        #expect(rest.chordSymbol?.raw == "Am")
        #expect(rest.annotations.map(\.text.value) == ["x"])
    }
}
