//
//  Event.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum Event: Sendable {
    case note(Note)
    case rest(Rest)
    case chord(Chord)            // unison / vertical chord — all notes share duration
    case grace(GraceGroup)       // attached to the following event
    case tuplet(Tuplet)
    case spacer(Spacer)
    case directiveAnchor(CeolKitDirective)   // a directive whose effect attaches to next event
    case tempoChange(Tempo)      // inline Q: field mid-tune
    /// A `K:` part way through a voice moved the staff to this clef (§4.6, issue #223).  It
    /// stands where the field was written, so the notes before it in the bar stay on the
    /// clef they were written against; one written against a bar line is the first event of
    /// the bar after it.  Not emitted for the clef a voice opens in, which is
    /// `Voice.properties.clef`.
    case clefChange(ClefSpec)
}
