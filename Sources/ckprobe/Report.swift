//
//  Report.swift
//  ckprobe
//
//  The probe's output, in both text and JSON form.
//

import CeolKitModel
import CeolKitSVGGeometry
import Foundation

/// Everything one run of the probe has to say.
struct Report: Codable {
    struct Diagnostic: Codable {
        let severity: String
        let code: String
        let message: String
        let line: Int
    }

    struct Stave: Codable {
        let measureCount: Int
        /// `Measure.source.line` for each measure.  A run of `1`s here is CeolKit #41,
        /// not a source file that really is all on line 1.
        let measureSourceLines: [Int]
    }

    struct Voice: Codable {
        let staves: [Stave]
    }

    struct Tune: Codable {
        let directives: [String]
        let voices: [Voice]
    }

    let file: String
    let diagnostics: [Diagnostic]
    let tunes: [Tune]
    let pages: [PageGeometry]
}

// MARK: - Building

extension Report {
    init(file: URL, score: Score, diagnostics: [CeolKitModel.Diagnostic], pages: [PageGeometry]) {
        self.file = file.lastPathComponent
        self.diagnostics = diagnostics.map {
            Diagnostic(severity: "\($0.severity)", code: "\($0.code)",
                       message: $0.message, line: $0.source.line)
        }
        self.tunes = score.tunes.map { tune in
            Tune(
                directives: tune.directives.map { "\($0.directive) @\($0.scope)" },
                voices: tune.voices.map { voice in
                    Voice(staves: voice.staves.map { stave in
                        Stave(measureCount: stave.measures.count,
                              measureSourceLines: stave.measures.map(\.source.line))
                    })
                }
            )
        }
        self.pages = pages
    }
}

// MARK: - Text rendering

extension Report {
    var text: String {
        var out: [String] = ["\(file)"]

        if diagnostics.isEmpty {
            out.append("  no diagnostics")
        } else {
            for diagnostic in diagnostics {
                out.append("  [\(diagnostic.severity)] line \(diagnostic.line): \(diagnostic.message)")
            }
        }

        out.append("")
        out.append("tunes: \(tunes.count)")
        for (tuneIndex, tune) in tunes.enumerated() {
            for directive in tune.directives {
                out.append("  tune[\(tuneIndex)] \(directive)")
            }
            for (voiceIndex, voice) in tune.voices.enumerated() {
                let counts = voice.staves.map(\.measureCount)
                out.append("  tune[\(tuneIndex)] voice[\(voiceIndex)] staves=\(voice.staves.count) measures/stave=\(counts)")
                for (staveIndex, stave) in voice.staves.enumerated() {
                    out.append("    stave[\(staveIndex)] measure source lines: \(stave.measureSourceLines)")
                }
            }
        }

        out.append("")
        out.append("pages: \(pages.count)")
        for (pageIndex, page) in pages.enumerated() {
            out.append("  page[\(pageIndex)] \(fmt(page.width)) x \(fmt(page.height)), systems: \(page.systems.count)")
            out.append("    " + Self.systemHeader)
            for (systemIndex, system) in page.systems.enumerated() {
                out.append("    " + row(systemIndex, system))
            }
        }

        return out.joined(separator: "\n")
    }

    /// Column alignment has to match `row(_:_:)` cell for cell, or the header floats.
    private static let systemHeader =
        pad("#", 3, alignRight: true) + "  " + pad("abcLine", 7, alignRight: true) + "  "
        + pad("staffGap", 8, alignRight: true) + "  " + pad("x-span", 15) + "  "
        + pad("width", 7, alignRight: true) + "  " + "barlines"

    private func row(_ index: Int, _ system: SystemGeometry) -> String {
        let span = "\(fmt(system.left))..\(fmt(system.right))"
        return Self.pad("\(index)", 3, alignRight: true) + "  "
            + Self.pad(system.abcLine.map(String.init) ?? "—", 7, alignRight: true) + "  "
            + Self.pad(fmt(system.staffLineGap), 8, alignRight: true) + "  "
            + Self.pad(span, 15) + "  "
            + Self.pad(fmt(system.width), 7, alignRight: true) + "  "
            + "\(system.barlineXs.count)"
    }

    /// `String(format:)` ignores field widths for `%@`, so pad by hand.
    static func pad(_ text: String, _ width: Int, alignRight: Bool = false) -> String {
        let padding = String(repeating: " ", count: max(0, width - text.count))
        return alignRight ? padding + text : text + padding
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
