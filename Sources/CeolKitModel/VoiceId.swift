//
//  VoiceId.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// Identifies a voice within a tune. The `.all` pseudo-voice (`*`) is used by `K:`
/// and transposition directives that apply across every voice simultaneously.
public enum VoiceId: Hashable {
    case named(String)   // "1", "soprano", "T1", etc.
    case all             // "*" — all-voices pseudo-voice
}
