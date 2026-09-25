//
//  DirectiveScopeTests.swift
//  CeolKitSVGRendererTests
//
//  Issue #153: a layout directive written in a tune header applies to that tune, and a
//  preamble one to the document (ABC v2.2 §4.23).
//

import CeolKitModel
import CeolKitParser
import Testing
@testable import CeolKitSVGRenderer

/// The four `%%ceolkit:*` directives the renderer resolves per tune, driven from the *first*
/// tune of a multi-tune document.
///
/// The existing suites (`ScaleDirectiveTests`, `GraceNoteSpacingDirectiveTests`) each check
/// that a directive on the *second* tune leaves the first alone, which is why they passed
/// while #153 was open: nothing before tune 2 can leak into tune 1. The leak only shows in
/// the other direction — a value set in tune 1's header and never reset — and in the layered
/// case where a tune between two others overrides the document and must not keep governing
/// after it.
@Suite("Directive scope across tunes (#153)")
struct DirectiveScopeTests {

    // MARK: - Sources

    /// `count` tunes of identical music, with `headers[i]` inserted into tune *i*'s header.
    ///
    /// Identical bodies throughout, so every difference measured below is the directive and
    /// nothing else — and the tunes are short enough to share one page, which is the
    /// arrangement that makes a leak observable at all.
    private func tunes(_ headers: [String?], body: String = "CDEF|") -> String {
        headers.enumerated().map { index, header in
            (["X:\(index + 1)", "T:Tune \(index + 1)", "M:4/4", "L:1/4", header, "K:C", body]
                as [String?])
                .compactMap { $0 }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    /// The same tunes with `preamble` standing above the first.
    private func tunes(preamble: String, _ headers: [String?],
                       body: String = "CDEF|") -> String {
        preamble + "\n" + tunes(headers, body: body)
    }

    // MARK: - Probes

    private func render(_ abc: String, config: SVGRenderConfig = SVGRenderConfig()) throws -> String {
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        return try SVGRenderer(config: config).render(score, diagnostics: &diagnostics).joined()
    }

    private struct StaffRun {
        /// Distance between adjacent staff lines — the tune's staff size, after `%%ceolkit:scale`.
        let spacing: Double
        /// Right-hand end of the staff lines, which is where justification put the system.
        let rightX: Double
    }

    /// One entry per system in `svg`, in document order.
    ///
    /// `emitStaffLines` opens each system with exactly five consecutive horizontal lines
    /// sharing one x range, which tells a staff apart from every other horizontal line on
    /// the page — ledger lines and beams come neither five to a run nor at a common x.
    private func staffRuns(in svg: String) -> [StaffRun] {
        let lines = svg.matches(of: /<line x1="([\d.-]+)" y1="([\d.-]+)" x2="([\d.-]+)" y2="([\d.-]+)"/)
            .compactMap { match -> (x1: Double, x2: Double, y: Double)? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      y1 == y2 else { return nil }
                return (x1, x2, y1)
            }
        var runs: [StaffRun] = []
        var i = 0
        while i + 4 < lines.count {
            let staff = lines[i ..< i + 5]
            if staff.allSatisfy({ $0.x1 == lines[i].x1 && $0.x2 == lines[i].x2 }) {
                runs.append(StaffRun(spacing: lines[i + 1].y - lines[i].y, rightX: lines[i].x2))
                i += 5
            } else {
                i += 1
            }
        }
        return runs
    }

    /// Whether the stems of each tune point up, one entry per tune, in document order.
    ///
    /// Every tune here carries the same four low notes on one system, so the tunes stack down
    /// the page and sorting the noteheads by y separates them exactly — see
    /// ``probedStemsByPitchGroup(in:staffSize:metadata:bucketCount:)``. The notes sit below
    /// the middle line, where the pitch rule stems *up*, so a tune stemming down is one the
    /// directive reached.
    private func stemsUpPerTune(_ abc: String, tuneCount: Int) throws -> [Bool] {
        let metadata = try BravuraMetadata.load()
        let config = SVGRenderConfig()
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try textProbeRenderer(config).render(score, diagnostics: &diagnostics).joined()
        let perTune = probedStemsByPitchGroup(in: svg, staffSize: config.staffSize,
                                              metadata: metadata, bucketCount: tuneCount)
        return try perTune.map { stems in
            try #require(!stems.isEmpty)
            let up = stems.filter(\.isUp).count
            // A tune's stems all go the same way here: every note of it is the same distance
            // from the middle line as the rest, and nothing in these tunes is beamed.
            #expect(up == 0 || up == stems.count)
            return up == stems.count
        }
    }

    // MARK: - %%ceolkit:scale

    @Test("A tune header %%ceolkit:scale does not resize the tune after it")
    func scaleDoesNotLeakForward() throws {
        let runs = staffRuns(in: try render(tunes(["%%ceolkit:scale 0.5", nil])))
        try #require(runs.count == 2)
        #expect(abs(runs[0].spacing - SVGRenderConfig().staffSize * 0.5) < 1e-9)
        #expect(runs[1].spacing == SVGRenderConfig().staffSize)
    }

    @Test("A preamble %%ceolkit:scale governs every tune")
    func preambleScaleGovernsDocument() throws {
        let runs = staffRuns(in: try render(tunes(preamble: "%%ceolkit:scale 0.5", [nil, nil])))
        try #require(runs.count == 2)
        #expect(runs.allSatisfy { abs($0.spacing - SVGRenderConfig().staffSize * 0.5) < 1e-9 })
    }

    @Test("A tune overriding a preamble %%ceolkit:scale does not keep governing after it")
    func tuneScaleOverrideIsNotSticky() throws {
        let runs = staffRuns(in: try render(
            tunes(preamble: "%%ceolkit:scale 0.8", [nil, "%%ceolkit:scale 1.2", nil])))
        try #require(runs.count == 3)
        let staffSize = SVGRenderConfig().staffSize
        #expect(abs(runs[0].spacing - staffSize * 0.8) < 1e-9)
        #expect(abs(runs[1].spacing - staffSize * 1.2) < 1e-9)
        #expect(abs(runs[2].spacing - staffSize * 0.8) < 1e-9)
    }

    // MARK: - %%ceolkit:gracenotespacing

    /// The grace beam spans `noteCount - 1` steps, so its length is proportional to the
    /// spacing factor — the same measurement `GraceNoteSpacingDirectiveTests` makes, reduced
    /// here to the one number these tests compare.  The beam also covers half a stem at each
    /// end (#181), which is taken off so the proportion holds exactly.
    private func graceBeamLengths(in svg: String) throws -> [Double] {
        let stem = try BravuraMetadata.load().engravingDefaults.stemThickness
                   * SVGRenderConfig().staffSize * GraceMetrics.scale
        let lines = svg.matches(of: /<line x1="([\d.-]+)" y1="([\d.-]+)" x2="([\d.-]+)" y2="([\d.-]+)"/)
            .compactMap { match -> (x1: Double, x2: Double, y: Double)? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3), let y2 = Double(match.4),
                      y1 == y2 else { return nil }
                return (x1, x2, y1)
            }
        // Staff lines come five to a run at a common x range; a grace beam does neither, and
        // sits above its own staff and below the staff before it.
        var tops: [Double] = []
        var staffLines: Set<Int> = []
        var i = 0
        while i + 4 < lines.count {
            let staff = lines[i ..< i + 5]
            if staff.allSatisfy({ $0.x1 == lines[i].x1 && $0.x2 == lines[i].x2 }) {
                tops.append(lines[i].y)
                staffLines.formUnion(i ..< i + 5)
                i += 5
            } else {
                i += 1
            }
        }
        let beams = lines.enumerated().filter { !staffLines.contains($0.offset) }.map(\.element)
        return try tops.enumerated().map { index, top in
            let floor = index == 0 ? -Double.infinity : tops[index - 1]
            let beam = try #require(beams.first { $0.y < top && $0.y > floor })
            return beam.x2 - beam.x1 - stem
        }
    }

    /// Quarter notes throughout, so the only beam on a system is the grace group's own.
    private static let graceBody = "{gcd}A A A A|"

    @Test("A tune header %%ceolkit:gracenotespacing does not respace the tune after it")
    func graceSpacingDoesNotLeakForward() throws {
        let svg = try render(tunes(["%%ceolkit:gracenotespacing 2.1", nil], body: Self.graceBody))
        let beams = try graceBeamLengths(in: svg)
        try #require(beams.count == 2)
        #expect(abs(beams[0] - beams[1] * 2.0) < 1e-6)
    }

    @Test("A tune overriding a preamble %%ceolkit:gracenotespacing is not sticky")
    func graceSpacingOverrideIsNotSticky() throws {
        let svg = try render(tunes(preamble: "%%ceolkit:gracenotespacing 2.1",
                                   [nil, "%%ceolkit:gracenotespacing 1.05", nil],
                                   body: Self.graceBody))
        let beams = try graceBeamLengths(in: svg)
        try #require(beams.count == 3)
        #expect(abs(beams[0] - beams[1] * 2.0) < 1e-6)
        #expect(abs(beams[2] - beams[0]) < 1e-9)
    }

    // MARK: - %%ceolkit:justifylast

    /// A one-system tune is all last system, so justifying it stretches the staff to the
    /// full usable width and leaving it alone stops it at the music's natural width.
    private func justifiedRightX(_ config: SVGRenderConfig) -> Double {
        config.pageSize.width - config.margins.right
    }

    @Test("A tune header %%ceolkit:justifylast does not stretch the tune after it")
    func justifyLastDoesNotLeakForward() throws {
        let config = SVGRenderConfig()
        let runs = staffRuns(in: try render(tunes(["%%ceolkit:justifylast true", nil]),
                                            config: config))
        try #require(runs.count == 2)
        #expect(abs(runs[0].rightX - justifiedRightX(config)) < 1e-6)
        #expect(runs[1].rightX < justifiedRightX(config) - 1)
    }

    @Test("A preamble %%ceolkit:justifylast governs every tune")
    func preambleJustifyLastGovernsDocument() throws {
        let config = SVGRenderConfig()
        let runs = staffRuns(in: try render(
            tunes(preamble: "%%ceolkit:justifylast true", [nil, nil]), config: config))
        try #require(runs.count == 2)
        #expect(runs.allSatisfy { abs($0.rightX - justifiedRightX(config)) < 1e-6 })
    }

    @Test("A tune turning a preamble %%ceolkit:justifylast off does not keep it off after")
    func justifyLastOverrideIsNotSticky() throws {
        let config = SVGRenderConfig()
        let runs = staffRuns(in: try render(
            tunes(preamble: "%%ceolkit:justifylast true",
                  [nil, "%%ceolkit:justifylast false", nil]), config: config))
        try #require(runs.count == 3)
        #expect(abs(runs[0].rightX - justifiedRightX(config)) < 1e-6)
        #expect(runs[1].rightX < justifiedRightX(config) - 1)
        #expect(abs(runs[2].rightX - justifiedRightX(config)) < 1e-6)
    }

    // MARK: - %%ceolkit:pipeformat

    @Test("A tune header %%ceolkit:pipeformat does not stem the tune after it down")
    func pipeFormatDoesNotLeakForward() throws {
        let stemsUp = try stemsUpPerTune(tunes(["%%ceolkit:pipeformat true", nil]), tuneCount: 2)
        #expect(stemsUp == [false, true])
    }

    @Test("A preamble %%ceolkit:pipeformat governs every tune")
    func preamblePipeFormatGovernsDocument() throws {
        let stemsUp = try stemsUpPerTune(tunes(preamble: "%%ceolkit:pipeformat true", [nil, nil]),
                                         tuneCount: 2)
        #expect(stemsUp == [false, false])
    }

    @Test("A tune turning a preamble %%ceolkit:pipeformat off does not keep it off after")
    func pipeFormatOverrideIsNotSticky() throws {
        // `pipeformat false` has to actively restore the pitch rule, not merely fail to set
        // the direction: before #153 it was dropped on the floor and tune 2 stayed down.
        let stemsUp = try stemsUpPerTune(
            tunes(preamble: "%%ceolkit:pipeformat true",
                  [nil, "%%ceolkit:pipeformat false", nil]), tuneCount: 3)
        #expect(stemsUp == [false, true, false])
    }
}
