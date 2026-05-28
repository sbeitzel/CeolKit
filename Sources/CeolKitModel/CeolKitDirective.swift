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
