//
//  CeolKitDirective.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum CeolKitDirective: Hashable {
    case pipeFormat(Bool)              // %%ceolkit:pipeformat true|false
    case pageNumber(Int)               // %%ceolkit:pagenumber N  (N >= 1)
    case stemAlignment(Int)            // %%ceolkit:stemalignment N  (signed integer)
}

public struct CeolKitDirectiveScope {
    public let directive: CeolKitDirective
    public let scope: Scope
    public let source: SourceRange
}

public enum Scope {
    case fileGlobal           // file preamble
    case tuneGlobal           // tune header
    case voiceLocal(VoiceId)  // body, immediately after V:
}
