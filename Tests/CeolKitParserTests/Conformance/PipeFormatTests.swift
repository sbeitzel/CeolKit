//
//  PipeFormatTests.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/29/26.
//

import CeolKitModel
import CeolKitParser
import Testing

private let kalabakan = """
    %abc-2.2
    %%ceolkit:pipeformat true
    %%footer "        Generated: $D"
    %%straightflags false
    %%flatbeams true
    %%graceslurs false
    %%dateformat "%e %B %Y %H:%M"
    %%landscape 1
    X:1
    T:Kalabakan (Borneo)
    R:Reel
    C:P/M A. MacDonald
    Z:abc-transcription Stephen Beitzel, <sbeitzel@pobox.com>, 2025-11-16
    M:C|
    L:1/8
    Q: 1/4 = 78
    K:D
    [|: A/ | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 :|]
    [| f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}f>e {Gdc}d2 {g}d>f |
    {ag}a2 f>a {g}a2>f {ag}a2 | {AGAG}A2 {g}B<d {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f<e {Gdc}d2 {g}d3/2 |]
    [| A/ | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d>A |
    {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>A {gAGAG}A2 {g}f>e{A}e>f | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 {g}d3/2 |]
    [| a/ | {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {g}B<d{e}A>d {g}B<{d}A{g}B<d | {g}f>e{A}e>f {gef}e2 a2 |
    {fg}f2 {g}f<a {ef}e2 {A}e>f | {Gdc}d2 {g}e>d {g}B<d{g}B<{d}A | {Gdc}d2 {e}A>d {g}B<{d}A{g}B<d | {g}A<{d}A{g}f>e {Gdc}d2 z |]
    """

@Suite("bagpipe formatting")
struct PipeFormatTests {
    let result = parse(kalabakan)
    var score: Score { result.score }

    @Test("Parse produces no error diagnostics")
    func noErrors() {
        let errors = score.errorDiagnostics
        #expect(errors.isEmpty, "Unexpected errors: \(errors.map(\.message))")
    }

    @Test("Parse produces no warning diagnostics")
    func noWarnings() {
        let warnings = score.warningDiagnostics
        #expect(warnings.isEmpty, "Unexpected warnings: \(warnings.map(\.message))")
    }
}
