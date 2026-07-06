import Testing
import Foundation
import CeolKitModel
import CeolKitParser

@Suite("I:abc-include directive")
struct IncludeDirectiveTests {

    // MARK: - Helper

    private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    // MARK: - No base directory (no-op)

    @Test("I:abc-include without base dir emits includeNoBaseDirectory warning")
    func noBaseDirEmitsWarning() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
        let result = CeolKitParser().parse(abc, options: .default)
        let warnings = result.score.diagnostics.filter { $0.code == .includeNoBaseDirectory }
        #expect(!warnings.isEmpty)
    }

    @Test("I:abc-include without base dir still produces a Tune")
    func noBaseDirStillProducesTune() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
        let result = CeolKitParser().parse(abc, options: .default)
        #expect(result.score.tunes.count == 1)
    }

    // MARK: - File not found

    @Test("I:abc-include nonexistent file emits includeFileNotFound error")
    func fileNotFoundEmitsError() throws {
        try withTempDir { dir in
            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include nonexistent.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            let errors = result.score.diagnostics.filter { $0.code == .includeFileNotFound }
            #expect(!errors.isEmpty)
        }
    }

    @Test("I:abc-include nonexistent file still produces a Tune")
    func fileNotFoundStillProducesTune() throws {
        try withTempDir { dir in
            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include nonexistent.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            #expect(result.score.tunes.count == 1)
        }
    }

    // MARK: - Successful include

    @Test("I:abc-include splices additional title from included file")
    func successfulIncludeAddsTitles() throws {
        try withTempDir { dir in
            let includeURL = dir.appendingPathComponent("extra.abc")
            try "T:Subtitle\nC:The Composer\n".write(to: includeURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:Main Title\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            #expect(result.score.tunes.count == 1)
            #expect(result.score.diagnostics.filter { $0.severity == .error }.isEmpty)
            let titles = result.score.tunes.first?.titles ?? []
            #expect(titles.count == 2)
        }
    }

    @Test("I:abc-include injects meter from included header file — notes parse correctly")
    func includeInjectsHeaderFields() throws {
        try withTempDir { dir in
            let includeURL = dir.appendingPathComponent("header.abc")
            try "M:4/4\nL:1/4\n".write(to: includeURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:Test\nI:abc-include header.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            #expect(result.score.tunes.count == 1)
            let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
            #expect(notes.count == 4)
        }
    }

    @Test("I:abc-include with no errors produces no include-related diagnostics")
    func successfulIncludeNoDiagnostics() throws {
        try withTempDir { dir in
            let includeURL = dir.appendingPathComponent("extra.abc")
            try "C:Some Composer\n".write(to: includeURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            let includeDiags = result.score.diagnostics.filter {
                $0.code == .includeNoBaseDirectory ||
                $0.code == .includeFileNotFound ||
                $0.code == .circularInclude
            }
            #expect(includeDiags.isEmpty)
        }
    }

    // MARK: - Circular include

    @Test("Circular include emits circularInclude error")
    func circularIncludeEmitsError() throws {
        try withTempDir { dir in
            let aURL = dir.appendingPathComponent("a.abc")
            let bURL = dir.appendingPathComponent("b.abc")
            try "I:abc-include b.abc\n".write(to: aURL, atomically: true, encoding: .utf8)
            try "I:abc-include a.abc\n".write(to: bURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include a.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            let errors = result.score.diagnostics.filter { $0.code == .circularInclude }
            #expect(!errors.isEmpty)
        }
    }

    @Test("Circular include still produces a Score without crashing")
    func circularIncludeStillProducesScore() throws {
        try withTempDir { dir in
            let aURL = dir.appendingPathComponent("a.abc")
            let bURL = dir.appendingPathComponent("b.abc")
            try "I:abc-include b.abc\n".write(to: aURL, atomically: true, encoding: .utf8)
            try "I:abc-include a.abc\n".write(to: bURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include a.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            _ = result.score
        }
    }

    // MARK: - fileResolver injection

    @Test("Default resolver reads from disk and emits usingDefaultFileResolver info diagnostic")
    func defaultResolverEmitsInfoDiagnostic() throws {
        try withTempDir { dir in
            let includeURL = dir.appendingPathComponent("extra.abc")
            try "C:Some Composer\n".write(to: includeURL, atomically: true, encoding: .utf8)

            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir).parse(abc, options: .default)
            let infos = result.score.diagnostics.filter { $0.code == .usingDefaultFileResolver }
            #expect(!infos.isEmpty)
            #expect(infos.allSatisfy { $0.severity == .info })
        }
    }

    @Test("Custom fileResolver supplies content without touching disk")
    func customResolverBypassesDisk() throws {
        try withTempDir { dir in
            // Note: extra.abc is never written to disk — only the resolver knows about it.
            let abc = "X:1\nT:Main Title\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir, fileResolver: { _ in
                Data("T:Subtitle\nC:The Composer\n".utf8)
            }).parse(abc, options: .default)

            #expect(result.score.tunes.count == 1)
            let titles = result.score.tunes.first?.titles ?? []
            #expect(titles.count == 2)
            let infos = result.score.diagnostics.filter { $0.code == .usingDefaultFileResolver }
            #expect(infos.isEmpty)
        }
    }

    @Test("Custom fileResolver receives the resolved include URL")
    func customResolverReceivesResolvedURL() throws {
        try withTempDir { dir in
            let expectedURL = dir.appendingPathComponent("extra.abc").standardized
            nonisolated(unsafe) var receivedURLs: [URL] = []

            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            _ = CeolKitParser(for: dir, fileResolver: { url in
                receivedURLs.append(url)
                return Data()
            }).parse(abc, options: .default)

            #expect(receivedURLs == [expectedURL])
        }
    }

    @Test("Custom fileResolver throwing surfaces as includeFileNotFound and still produces a Tune")
    func customResolverThrowingEmitsError() throws {
        struct ResolverFailure: Error {}
        try withTempDir { dir in
            let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir, fileResolver: { _ in
                throw ResolverFailure()
            }).parse(abc, options: .default)

            let errors = result.score.diagnostics.filter { $0.code == .includeFileNotFound }
            #expect(!errors.isEmpty)
            #expect(result.score.tunes.count == 1)
        }
    }

    @Test("fileResolver is not invoked when there is no base directory")
    func resolverNotInvokedWithoutBaseDir() {
        nonisolated(unsafe) var wasCalled = false
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nI:abc-include extra.abc\nK:C\nCDEF|\n"
        let result = CeolKitParser(fileResolver: { url in
            wasCalled = true
            return Data()
        }).parse(abc, options: .default)

        #expect(!wasCalled)
        let warnings = result.score.diagnostics.filter { $0.code == .includeNoBaseDirectory }
        #expect(!warnings.isEmpty)
    }

    @Test("Custom fileResolver is reused across nested includes")
    func customResolverReusedAcrossNestedIncludes() throws {
        try withTempDir { dir in
            // Neither file exists on disk — the resolver serves both levels from memory.
            let content: [String: String] = [
                dir.appendingPathComponent("a.abc").standardized.path: "I:abc-include b.abc\nT:From A\n",
                dir.appendingPathComponent("b.abc").standardized.path: "T:From B\n",
            ]

            let abc = "X:1\nT:Main\nM:4/4\nL:1/4\nI:abc-include a.abc\nK:C\nCDEF|\n"
            let result = CeolKitParser(for: dir, fileResolver: { url in
                guard let text = content[url.path] else { throw CocoaError(.fileNoSuchFile) }
                return Data(text.utf8)
            }).parse(abc, options: .default)

            #expect(result.score.tunes.count == 1)
            let titles = result.score.tunes.first?.titles ?? []
            #expect(titles.count == 3)
        }
    }

    // MARK: - Inline I:abc-include

    @Test("Inline [I:abc-include] in music body emits includeIgnoredInline warning")
    func inlineIncludeEmitsWarning() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n[I:abc-include file.abc]CDEF|\n"
        let result = CeolKitParser().parse(abc, options: .default)
        let warnings = result.score.diagnostics.filter { $0.code == .includeIgnoredInline }
        #expect(!warnings.isEmpty)
    }

    @Test("Inline [I:abc-include] does not prevent surrounding notes from parsing")
    func inlineIncludePreservesNotes() {
        let abc = "X:1\nT:T\nM:4/4\nL:1/4\nK:C\n[I:abc-include file.abc]CDEF|\n"
        let result = CeolKitParser().parse(abc, options: .default)
        let notes = result.score.firstTune?.singleVoiceMeasures.first?.noteEvents ?? []
        #expect(notes.count == 4)
    }
}
