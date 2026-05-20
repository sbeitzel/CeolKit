//
//  Mode.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// The modal quality of a key signature. Church modes share names with `.major` (Ionian)
/// and `.minor` (Aeolian) but are listed explicitly so callers never need string comparison.
/// `.none` corresponds to `K:none` (no key signature, all naturals).
/// `.highlandPipes` and `.highlandPipesNoSignature` correspond to `K:HP` and `K:Hp`.
public enum Mode: Hashable {
    case major
    case minor
    case ionian
    case dorian
    case phrygian
    case lydian
    case mixolydian
    case aeolian
    case locrian
    case none                    // K:none — no key signature
    case highlandPipes           // K:HP  — F# and C# implicit, not drawn on staff
    case highlandPipesNoSignature // K:Hp  — no sharps drawn
}
