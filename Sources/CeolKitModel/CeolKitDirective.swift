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
    case landscape(Bool)               // %%landscape 0|1  (ABC v2.2 §9.1)
    case flatBeams(Bool)               // %%flatbeams true|false  (abcm2ps; implicit in pipeFormat)
    case justifyLast(Bool)             // %%ceolkit:justifylast true|false
    case titleFormat(String)           // %%titleformat <format-string>  (abcm2ps/abc2svg)
    case dateFormat(String)            // %%dateformat <strftime-string>  (abcm2ps/abc2svg)
    case straightFlags(Bool)           // %%straightflags bool  (abcm2ps/abc2svg)
    case graceSlurs(Bool)              // %%graceslurs bool      (abcm2ps/abc2svg)
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
