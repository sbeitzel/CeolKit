//
//  VoiceOverlay.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// One temporary voice an `&` opens on a stave (ABC v2.2 §7.4).
///
/// > The `&` operator may be used to temporarily overlay several voices within one measure.
/// > Each `&` operator sets the time point of the music back by one bar line, and the notes
/// > which follow it form a temporary voice in parallel with the preceding one.
///
/// An overlay is a second tenant of the staff its voice is drawn on, exactly as the voices of
/// a `%%score ( … )` group are, and the renderer feeds it through the same onset-keyed merge.
///
/// **``measures`` is parallel to the stave's own.**  There is one entry per bar of
/// ``Staff/measures``, in the same order, and a bar the overlay says nothing in is an entry
/// with no events rather than a gap.  A layer that is silent for a whole stave is therefore
/// still present there: an overlay's position in ``Staff/overlays`` is its identity — the
/// *n*th layer of a voice is the same temporary voice on every stave of it — and a layer that
/// came and went between staves would silently become a different one.
public struct VoiceOverlay: Sendable {
    /// One measure per measure of the stave this overlay belongs to.
    public let measures: [Measure]
    /// The `&` that opened this layer.
    public let source: SourceRange

    public init(measures: [Measure], source: SourceRange) {
        self.measures = measures
        self.source = source
    }
}
