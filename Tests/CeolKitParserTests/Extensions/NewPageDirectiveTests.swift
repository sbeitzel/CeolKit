// Where a %%newpage takes effect (ABC v2.2 §11.4.7, issue #140).
// Parser and model only — pagination itself is checked in the renderer's NewPageTests.
import Testing
import CeolKitModel
import CeolKitParser

@Suite("%%newpage position (#140)")
struct NewPageDirectiveTests {

    // MARK: - Helpers

    private func breaks(_ abc: String, tune index: Int = 0) -> [PageBreak] {
        let tunes = parse(abc).score.tunes
        guard tunes.indices.contains(index) else { return [] }
        return tunes[index].pageBreaks
    }

    private func diagnostics(_ abc: String, code: DiagnosticCode) -> [Diagnostic] {
        parse(abc).score.diagnostics.filter { $0.code == code }
    }

    // MARK: - Nothing to report

    @Test("A tune with no %%newpage asks for no break")
    func noDirective() {
        #expect(breaks("""
        X:1
        L:1/4
        K:C
        CDEF|
        """).isEmpty)
    }

    @Test("%%newpage no longer reports itself as an unsupported directive")
    func noLongerUnknown() {
        let unknown = diagnostics("""
        %%newpage
        X:1
        L:1/4
        K:C
        CDEF|
        """, code: .unknownDirective)
        #expect(unknown.isEmpty)
    }

    // MARK: - Where the break lands

    @Test("A header %%newpage breaks before the tune's first stave")
    func headerBreak() throws {
        let found = breaks("""
        X:1
        %%newpage
        L:1/4
        K:C
        CDEF|
        """)
        try #require(found.count == 1)
        #expect(found[0].beforeStave == 0)
        #expect(found[0].restartingAt == nil)
    }

    @Test("A body %%newpage breaks before the stave that follows it")
    func bodyBreak() throws {
        let found = breaks("""
        X:1
        L:1/4
        K:C
        CDEF|
        GABc|
        %%newpage
        CDEF|
        """)
        try #require(found.count == 1)
        #expect(found[0].beforeStave == 2)
    }

    @Test("A %%newpage below the last stave breaks past the end of the tune")
    func trailingBreak() throws {
        let found = breaks("""
        X:1
        L:1/4
        K:C
        CDEF|
        %%newpage
        """)
        try #require(found.count == 1)
        #expect(found[0].beforeStave == 1)
    }

    @Test("A %%newpage in the gap between two tunes belongs to the tune below it")
    func gapBreakBelongsToTheFollowingTune() throws {
        let abc = """
        X:1
        L:1/4
        K:C
        CDEF|

        %%newpage
        X:2
        L:1/4
        K:C
        GABc|
        """
        #expect(breaks(abc, tune: 0).isEmpty)
        let second = breaks(abc, tune: 1)
        try #require(second.count == 1)
        #expect(second[0].beforeStave == 0)
    }

    @Test("A %%newpage past the last tune is dropped, and says so")
    func orphanBreak() throws {
        let abc = """
        X:1
        L:1/4
        K:C
        CDEF|

        %%newpage
        """
        #expect(breaks(abc).isEmpty)
        #expect(diagnostics(abc, code: .pageBreakAfterLastTune).count == 1)
    }

    // MARK: - Snapping

    @Test("A %%newpage part way through a stave snaps back to the start of it")
    func snapsToStave() throws {
        let abc = """
        X:1
        L:1/4
        V:1
        V:2
        K:C
        [V:1]CDEF|
        %%newpage
        [V:2]GABc|
        [V:1]CDEF|
        [V:2]GABc|
        """
        let found = breaks(abc)
        try #require(found.count == 1)
        #expect(found[0].beforeStave == 0)
        #expect(diagnostics(abc, code: .pageBreakSnappedToStave).count == 1)
    }

    @Test("A %%newpage on a line-set boundary does not snap, and is not warned about")
    func boundaryDoesNotSnap() throws {
        let abc = """
        X:1
        L:1/4
        V:1
        V:2
        K:C
        [V:1]CDEF|
        [V:2]GABc|
        %%newpage
        [V:1]CDEF|
        [V:2]GABc|
        """
        let found = breaks(abc)
        try #require(found.count == 1)
        #expect(found[0].beforeStave == 1)
        #expect(diagnostics(abc, code: .pageBreakSnappedToStave).isEmpty)
    }

    // MARK: - The optional page number

    @Test("%%newpage N carries the number the new page prints")
    func carriesNumber() throws {
        let found = breaks("""
        X:1
        %%newpage 20
        L:1/4
        K:C
        CDEF|
        """)
        try #require(found.count == 1)
        #expect(found[0].restartingAt == 20)
    }

    @Test("An argument that is not a page number leaves the break standing")
    func badArgumentKeepsTheBreak() throws {
        // The author unmistakably asked for a page break; only the renumbering is in doubt.
        let abc = """
        X:1
        %%newpage frog
        L:1/4
        K:C
        CDEF|
        """
        let found = breaks(abc)
        try #require(found.count == 1)
        #expect(found[0].restartingAt == nil)
        #expect(diagnostics(abc, code: .invalidPageNumber).count == 1)
    }

    @Test("Page numbers below 1 are refused the same way")
    func zeroIsRefused() throws {
        let abc = """
        X:1
        %%newpage 0
        L:1/4
        K:C
        CDEF|
        """
        let found = breaks(abc)
        try #require(found.count == 1)
        #expect(found[0].restartingAt == nil)
        #expect(diagnostics(abc, code: .invalidPageNumber).count == 1)
    }

    // MARK: - Not a flattened directive

    @Test("A page break is not also stored as a CeolKitDirective")
    func notInDirectives() {
        // It has no meaning apart from where it falls, so the positional list is the only
        // view of it — nothing downstream should find a last-wins scalar to read instead.
        let tune = parse("""
        %%newpage 4
        X:1
        L:1/4
        K:C
        CDEF|
        """).score.firstTune
        let directives = tune?.directives ?? []
        #expect(directives.isEmpty)
    }
}
