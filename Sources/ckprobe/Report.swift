//
//  Report.swift
//  ckprobe
//
//  The probe's output, in both text and JSON form.
//

import CeolKitModel
import CeolKitSVGGeometry
import CeolKitSVGRenderer
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
        /// `Measure.source.line` for each measure.  These should track the source
        /// lines the music is written on; a run of `1`s means the semantic pass has
        /// lost the positions again (the defect behind CeolKit #41).
        let measureSourceLines: [Int]
    }

    struct Voice: Codable {
        let staves: [Stave]
    }

    /// One `%%score` / `%%staves` and the stave it governs from, so that a body plan's
    /// position can be read off without re-deriving it from the source.
    struct StaffPlanChange: Codable {
        let effectiveFromStave: Int
        let line: Int
        /// The voices of each staff, top to bottom.
        let staves: [[String]]
    }

    /// One `%%newpage` and the stave it breaks before, so that a body break's position can
    /// be read off without re-deriving it from the source.
    struct PageBreak: Codable {
        let beforeStave: Int
        let line: Int
        /// The number the new page prints, or `nil` where the directive carried none.
        let restartingAt: Int?
    }

    struct Tune: Codable {
        let directives: [String]
        let staffPlans: [StaffPlanChange]
        let pageBreaks: [PageBreak]
        let voices: [Voice]
    }

    /// Where one tune came out once the document was packed (CeolKit #152).  Not derivable
    /// from the emitted SVG: tunes share pages, so the page a tune starts on is a fact only
    /// the layout holds.
    struct Placement: Codable {
        let tuneIndex: Int
        let pageIndex: Int
        let printedPageNumber: Int
        let topY: Double
    }

    /// What one kind of text in a tune was set in (CeolKit #191).
    struct Font: Codable {
        let role: String
        /// The font directives' (or host's) request, as written; absent for the default.
        let requestedName: String?
        let requestedSize: Double?
        /// The line of the directive that named the face, where one did.
        let line: Int?
        let postScriptName: String
        let family: String
        let weight: String
        let style: String
        let origin: String
        let size: Double
        let exact: Bool
        let summary: String
    }

    let file: String
    let diagnostics: [Diagnostic]
    let tunes: [Tune]
    let placements: [Placement]
    /// Per tune, in score order.
    let fonts: [[Font]]
    let pages: [PageGeometry]
}

// MARK: - Building

extension Report {
    init(file: URL, score: Score, diagnostics: [CeolKitModel.Diagnostic],
         placements: [TunePlacement], fonts: [TuneFontReport], pages: [PageGeometry]) {
        self.file = file.lastPathComponent
        self.diagnostics = diagnostics.map {
            Diagnostic(severity: "\($0.severity)", code: "\($0.code)",
                       message: $0.message, line: $0.source.line)
        }
        self.tunes = score.tunes.map { tune in
            Tune(
                directives: tune.directives.map { "\($0.directive) @\($0.scope)" },
                staffPlans: tune.staffPlans.map { change in
                    StaffPlanChange(
                        effectiveFromStave: change.effectiveFromStave,
                        line: change.source.line,
                        staves: change.plan.layout.staves.map { $0.map(name) }
                    )
                },
                pageBreaks: tune.pageBreaks.map {
                    PageBreak(beforeStave: $0.beforeStave, line: $0.source.line,
                              restartingAt: $0.restartingAt)
                },
                voices: tune.voices.map { voice in
                    Voice(staves: voice.staves.map { stave in
                        Stave(measureCount: stave.measures.count,
                              measureSourceLines: stave.measures.map(\.source.line))
                    })
                }
            )
        }
        self.placements = placements.map {
            Placement(tuneIndex: $0.tuneIndex, pageIndex: $0.pageIndex,
                      printedPageNumber: $0.printedPageNumber, topY: $0.topY)
        }
        self.fonts = fonts.map { tune in
            tune.roles.map { role in
                Font(role: role.role.rawValue, requestedName: role.requested?.name,
                     requestedSize: role.requested?.size, line: role.source?.line,
                     postScriptName: role.resolution.postScriptName,
                     family: role.resolution.family,
                     weight: role.resolution.weight.rawValue,
                     style: role.resolution.style.rawValue,
                     origin: role.resolution.origin.rawValue, size: role.size,
                     exact: role.resolution.isExact, summary: role.summary)
            }
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
            for plan in tune.staffPlans {
                let staves = plan.staves.map { $0.joined(separator: "+") }.joined(separator: " / ")
                out.append("  tune[\(tuneIndex)] staffPlan from stave \(plan.effectiveFromStave)"
                           + " (line \(plan.line)): \(staves)")
            }
            for pageBreak in tune.pageBreaks {
                let restart = pageBreak.restartingAt.map { ", renumbering from \($0)" } ?? ""
                out.append("  tune[\(tuneIndex)] newpage before stave \(pageBreak.beforeStave)"
                           + " (line \(pageBreak.line))\(restart)")
            }
            for (voiceIndex, voice) in tune.voices.enumerated() {
                let counts = voice.staves.map(\.measureCount)
                out.append("  tune[\(tuneIndex)] voice[\(voiceIndex)] staves=\(voice.staves.count) measures/stave=\(counts)")
                for (staveIndex, stave) in voice.staves.enumerated() {
                    out.append("    stave[\(staveIndex)] measure source lines: \(stave.measureSourceLines)")
                }
            }
        }

        if !placements.isEmpty {
            out.append("")
            out.append("placements:")
            for placement in placements {
                out.append("  tune[\(placement.tuneIndex)] page[\(placement.pageIndex)]"
                           + " printed \(placement.printedPageNumber), topY \(fmt(placement.topY))")
            }
        }

        if fonts.contains(where: { !$0.isEmpty }) {
            out.append("")
            out.append("fonts:")
            for (tuneIndex, roles) in fonts.enumerated() {
                for font in roles {
                    let line = font.line.map { " (line \($0))" } ?? ""
                    out.append("  tune[\(tuneIndex)] \(font.summary)\(line)")
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

    /// `--fonts`: one face per line, in the order a request searches them.
    static func fontTable(_ faces: [FontFaceInfo]) -> String {
        let width = faces.map(\.postScriptName.count).max() ?? 0
        var out = [pad("postScriptName", width) + "  " + pad("origin", 10) + "  "
                   + pad("format", 8) + "  " + pad("weight", 7) + "  " + pad("style", 7)
                   + "  " + "family"]
        for face in faces {
            out.append(pad(face.postScriptName, width) + "  " + pad(face.origin.rawValue, 10)
                       + "  " + pad(face.format.rawValue, 8) + "  "
                       + pad(face.weight.rawValue, 7) + "  " + pad(face.style.rawValue, 7)
                       + "  " + face.family + (face.embeddable ? "" : "  (not embeddable)"))
        }
        out.append("\(faces.count) faces")
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


/// `VoiceId` printed the way the source wrote it.
private func name(_ id: VoiceId) -> String {
    switch id {
    case .named(let n): return n
    case .all:          return "*"
    }
}
