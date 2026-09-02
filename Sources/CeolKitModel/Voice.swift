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
    /// The key signature this voice opens in, or `nil` when it states none of its own and the
    /// tune's `K:` governs — the signature to draw at the head of its staff.
    ///
    /// ABC §7.3 asks for a field that sets a music property to be repeated in every voice it
    /// applies to, which only means anything if one voice's `K:` leaves the others alone.  A
    /// voice that never writes a `K:` keeps `nil` here rather than a copy of the tune's, so
    /// "states its own key" stays distinguishable from "agrees with the tune"; use
    /// ``Tune/effectiveKey(for:)`` to resolve the two.
    ///
    /// A `K:` written part way through the voice changes how its accidentals resolve from
    /// that point on, but does not appear here: it is a key change mid-staff, not the key the
    /// staff opens in.
    public let key: KeySignature?
    /// The unit note length this voice's durations are written against, or `nil` when the
    /// tune's `L:` governs.  See ``Tune/effectiveUnitNoteLength(for:)``.
    public let unitNoteLength: Fraction?
    public let staves: [Staff]                   // usually 1; > 1 for grand staff voices
    public let directives: [CeolKitDirectiveScope]
    public let source: SourceRange

    public init(
        id: VoiceId,
        properties: VoiceProperties,
        key: KeySignature? = nil,
        unitNoteLength: Fraction? = nil,
        staves: [Staff],
        directives: [CeolKitDirectiveScope],
        source: SourceRange
    ) {
        self.id = id
        self.properties = properties
        self.key = key
        self.unitNoteLength = unitNoteLength
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
