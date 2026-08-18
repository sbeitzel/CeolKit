//
//  Voice.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Voice: Sendable {
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

    /// True when no stave of this voice holds a measure — a voice a `V:` field declared and
    /// the tune body never wrote to.
    ///
    /// Such a voice is part of the model so that a `%%score` plan can name it, but it is not
    /// printed: ABC §11.1 prints "all voices that appear in the tune body", and this one does
    /// not appear there.  Renderers filter on this before laying staves out.
    public var isEmpty: Bool { staves.allSatisfy(\.measures.isEmpty) }
}
