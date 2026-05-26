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
}
