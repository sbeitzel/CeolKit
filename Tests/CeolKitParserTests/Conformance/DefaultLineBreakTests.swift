// §6.1.1 Default line-break behavior
//
// ABC 2.2 §6.1.1 states: "The default line-break setting is: I:linebreak <EOL> $"
// meaning that both source code line-breaks and $ symbols generate score line-breaks
// when no I:linebreak directive is present at all.
//
// CeolKit currently initialises linebreakOnEOL = false, so tunes without an explicit
// I:linebreak directive produce no stave splits at EOL — this is wrong.
import Testing
import CeolKitModel
import CeolKitParser

// A tune with three lines of music code and no I:linebreak directive.
// Each source line-break should produce a stave boundary.
private let threeLineABC = """
X:1
T:EOL Linebreak Default Test
M:4/4
L:1/4
K:C
CDEF|GABC|
DEFG|ABCD|
EFGA|BCDE|
"""

// A tune that explicitly opts out of automatic line-breaking with <none>.
// All three source lines should collapse into a single stave.
private let noLineBreakABC = """
X:1
T:No Linebreak Test
I:linebreak <none>
M:4/4
L:1/4
K:C
CDEF|GABC|
DEFG|ABCD|
EFGA|BCDE|
"""

@Suite("§6.1.1 Default line-break behavior")
struct DefaultLineBreakTests {

    // MARK: - Default (no I:linebreak directive)

    @Test("Parse produces no error diagnostics")
    func noErrors() {
        let score = parse(threeLineABC).score
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    @Test("Without I:linebreak directive, each source line produces a stave break (default is <EOL> $)")
    func defaultEOLProducesStaveBreak() {
        let score = parse(threeLineABC).score
        guard let tune = score.tunes.first else { Issue.record("No tune parsed"); return }
        let staves = tune.voices.first?.staves ?? []
        // 3 source music lines → 3 staves under default I:linebreak <EOL> $ behaviour
        #expect(staves.count == 3, "Expected 3 staves (one per source line), got \(staves.count)")
    }

    // MARK: - Explicit I:linebreak <none> (reference: all-automatic, no EOL splits)

    @Test("I:linebreak <none> suppresses all EOL stave breaks")
    func explicitNoneSuppressesBreaks() {
        let score = parse(noLineBreakABC).score
        guard let tune = score.tunes.first else { Issue.record("No tune parsed"); return }
        let staves = tune.voices.first?.staves ?? []
        // <none> means automatic layout only — all source lines merge into one system
        #expect(staves.count == 1, "Expected 1 stave with I:linebreak <none>, got \(staves.count)")
    }
}
