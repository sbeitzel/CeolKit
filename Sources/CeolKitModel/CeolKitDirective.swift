//
//  CeolKitDirective.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum CeolKitDirective: Hashable, Sendable {
    case pipeFormat(Bool)              // %%ceolkit:pipeformat true|false
    case pageNumber(Int)               // %%ceolkit:pagenumber N  (N >= 1)
    case stemAlignment(Int)            // %%ceolkit:stemalignment N  (signed integer)
    /// The page scale, as abcm2ps's `%%scale` value (issue #203): `0.75` is abcm2ps's — and
    /// CeolKit's — default.  `%%scale S` is `.scale(S)`; `%%pagescale F` and the deprecated
    /// `%%ceolkit:scale F` are both `.scale(0.75 × F)`.
    case scale(Double)                 // %%scale S | %%pagescale F | %%ceolkit:scale F  (> 0)
    case graceNoteSpacing(Double)      // %%ceolkit:gracenotespacing F  (F >= 1)
    case landscape(Bool)               // %%landscape 0|1  (ABC v2.2 §9.1)
    case flatBeams(Bool)               // %%flatbeams true|false  (abcm2ps; implicit in pipeFormat)
    /// How short the last system of a tune may be and still be stretched to the full line,
    /// as abcm2ps's `%%stretchlast` value (issue #198): the system is stretched when its
    /// natural width reaches `1 − F` of the line.  `0.25` is abcm2ps's — and CeolKit's —
    /// default; `0` never stretches it, `1` always does.  The spec's logical form and the
    /// deprecated `%%ceolkit:justifylast` are `1` for true and `0` for false.
    case stretchLast(Double)           // %%stretchlast F (0…1) | true|false | %%ceolkit:justifylast
    /// Whether systems are stretched to the line at all, from `%%stretchstaff` (ABC v2.2
    /// §11.4.3 lists it; abcm2ps defaults it to true).  `false` draws every system at its
    /// natural width, the last one included.
    case stretchStaff(Bool)            // %%stretchstaff true|false
    case label(String)                 // %%ceolkit:label "<text>"  (value of a `${label}` footer mark)
    case writeFields(String, Bool)     // %%writefields <fieldList> [true|false]  (ABC v2.2 §11.4.6)
    case dateFormat(String)            // %%dateformat <strftime-string>  (abcm2ps/abc2svg)
    case straightFlags(Bool)           // %%straightflags bool  (abcm2ps/abc2svg)
    case graceSlurs(Bool)              // %%graceslurs bool      (abcm2ps/abc2svg)
    case staffPlan(StaffPlan)          // %%score / %%staves     (ABC v2.2 §11.1)
    case font(TextFontRole, FontSpec)  // %%titlefont, %%gchordfont, … <name> [<size>]  (§11.4.2)
    case fontList(FontListMode)        // %%ceolkit:fontlist [resolved|available]  (issue #191)
}

public struct CeolKitDirectiveScope: Sendable {
    public let directive: CeolKitDirective
    public let scope: Scope
    public let source: SourceRange

    public init(directive: CeolKitDirective, scope: Scope, source: SourceRange) {
        self.directive = directive
        self.scope = scope
        self.source = source
    }
}

public enum Scope: Sendable {
    case fileGlobal           // file preamble
    case tuneGlobal           // tune header
    case voiceLocal(VoiceId)  // body, immediately after V:
}
