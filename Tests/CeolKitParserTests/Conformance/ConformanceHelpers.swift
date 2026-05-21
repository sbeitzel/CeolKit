import Testing
import CeolKitModel
import CeolKitParser

// MARK: - Navigation helpers

extension Measure {
    var noteEvents: [Note] {
        events.compactMap { if case .note(let n) = $0 { n } else { nil } }
    }

    var chordEvents: [Chord] {
        events.compactMap { if case .chord(let c) = $0 { c } else { nil } }
    }

    var restEvents: [Rest] {
        events.compactMap { if case .rest(let r) = $0 { r } else { nil } }
    }

    var tupletEvents: [Tuplet] {
        events.compactMap { if case .tuplet(let t) = $0 { t } else { nil } }
    }

    var graceEvents: [GraceGroup] {
        events.compactMap { if case .grace(let g) = $0 { g } else { nil } }
    }
}

extension Voice {
    var firstStaff: Staff? { staves.first }
    var allMeasures: [Measure] { staves.flatMap(\.measures) }
    var firstMeasure: Measure? { staves.first?.measures.first }
}

extension Tune {
    var firstVoice: Voice? { voices.first }
    var singleVoiceMeasures: [Measure] { voices.first?.allMeasures ?? [] }
}

extension Score {
    var firstTune: Tune? { tunes.first }
    var errorDiagnostics: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
    var warningDiagnostics: [Diagnostic] { diagnostics.filter { $0.severity == .warning } }
}

// MARK: - Convenience parse

func parse(_ source: String, options: ParseOptions = .default) -> ParseResult {
    CeolKitParser().parse(source, options: options)
}
