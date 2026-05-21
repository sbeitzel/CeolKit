//
//  Voice.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Voice {
    public let id: VoiceId                       // "1", "soprano", etc.; "*" for all-voice
    public let properties: VoiceProperties       // clef, stafflines, transpose, name, subname, …
    public let staves: [Staff]                   // usually 1; > 1 for grand staff voices
    public let directives: [CeolKitDirectiveScope]
    public let source: SourceRange

    public init(
        id: VoiceId,
        properties: VoiceProperties,
        staves: [Staff],
        directives: [CeolKitDirectiveScope],
        source: SourceRange
    ) {
        self.id = id
        self.properties = properties
        self.staves = staves
        self.directives = directives
        self.source = source
    }
}
