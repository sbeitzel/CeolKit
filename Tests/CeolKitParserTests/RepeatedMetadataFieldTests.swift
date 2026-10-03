import Foundation
import Testing
import CeolKitModel
@testable import CeolKitParser

/// Issue #188: a repeated string-type field adds information rather than replacing what came
/// before it (ABC v2.2 §3), so every occurrence is kept, in source order.
@Suite("Repeated string fields keep every value")
struct RepeatedMetadataFieldTests {

    private func metadata(_ header: String) -> TuneMetadata {
        let abc = "X:1\nT:t\n" + header + "\nK:C\nC|]\n"
        return CeolKitParser().parse(abc, options: .default).score.tunes[0].metadata
    }

    @Test("Three N: lines give three notes, in source order")
    func repeatedNotes() {
        let meta = metadata("""
        N:Audio: https://avaleg.fr/MID/laMiranda.mid
        N:Piano: https://avaleg.fr/PI/laMiranda-PI.pdf
        N:Clarinette: https://avaleg.fr/CL/laMiranda-CL.pdf
        """)
        #expect(meta.notes.map(\.value) == [
            "Audio: https://avaleg.fr/MID/laMiranda.mid",
            "Piano: https://avaleg.fr/PI/laMiranda-PI.pdf",
            "Clarinette: https://avaleg.fr/CL/laMiranda-CL.pdf",
        ])
    }

    @Test("Two C: lines give two composers, in source order")
    func repeatedComposers() {
        let meta = metadata("C:John Lennon\nC:Paul McCartney")
        #expect(meta.composer.map(\.value) == ["John Lennon", "Paul McCartney"])
    }

    @Test("Every other string field accumulates the same way")
    func everyFieldAccumulates() {
        let meta = metadata("""
        A:a1
        A:a2
        B:b1
        B:b2
        D:d1
        D:d2
        F:https://example.com/1
        F:https://example.com/2
        G:g1
        G:g2
        S:s1
        S:s2
        R:r1
        R:r2
        Z:z1
        Z:z2
        """)
        #expect(meta.area.map(\.value) == ["a1", "a2"])
        #expect(meta.book.map(\.value) == ["b1", "b2"])
        #expect(meta.discography.map(\.value) == ["d1", "d2"])
        #expect(meta.fileURL.map(\.absoluteString)
                == ["https://example.com/1", "https://example.com/2"])
        #expect(meta.group.map(\.value) == ["g1", "g2"])
        #expect(meta.source.map(\.value) == ["s1", "s2"])
        #expect(meta.rhythm.map(\.value) == ["r1", "r2"])
        #expect(meta.transcription.map(\.value) == ["z1", "z2"])
    }

    @Test("An absent field is an empty list")
    func absentFieldIsEmpty() {
        let meta = metadata("")
        #expect(meta.composer.isEmpty)
        #expect(meta.notes.isEmpty)
        #expect(meta.fileURL.isEmpty)
    }
}
