//
//  Decoration.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// The resolved, normalised form of a decoration after the semantic pass.
/// Short-form decorations (`. ~ H L M O P S T u v`) are expanded to their
/// canonical cases during the semantic pass; consumers see only this type.
public enum Decoration: Hashable, Sendable {

    // Dynamics
    case ppp                    // !ppp!
    case pp                     // !pp!
    case p                      // !p!
    case mp                     // !mp!
    case mf                     // !mf!
    case f                      // !f!
    case ff                     // !ff!
    case fff                    // !fff!
    case sfz                    // !sfz!

    // Articulations
    case staccato               // !staccato! / .
    case staccatissimo          // !staccatissimo!
    case tenuto                 // !tenuto!
    case accent                 // !accent! / L
    case strongAccent           // !>!
    case arpeggio               // !arpeggio!

    // Ornaments
    case trill                  // !trill! / T
    case trillStart             // !trill(!
    case trillEnd               // !trill)!
    case mordent                // !mordent! / M
    case pralltriller           // !pralltriller! / P
    case roll                   // !roll! / ~
    case turn                   // !turn!
    case invertedTurn           // !invertedturn!

    // Fermatas
    case fermata                // !fermata! / H
    case invertedFermata        // !invertedfermata!

    // Bowing / technique
    case upbow                  // !upbow! / u
    case downbow                // !downbow! / v
    case open                   // !open!
    case snap                   // !snap!
    case thumb                  // !thumb!
    case plus                   // !+!  (left-hand pizzicato / stopped horn)
    case fingering(Int)         // !0! … !5!

    // Hairpins (single-event anchors)
    case crescendoStart         // !<(!
    case crescendoEnd           // !<)!
    case decrescendoStart       // !>(!
    case decrescendoEnd         // !>)!

    // Navigation / repeat signs
    case segno                  // !segno! / S
    case coda                   // !coda! / O
    case fine                   // !fine!
    case dacapo                 // !D.C.!
    case dacapoAlFine           // !D.C.al Fine!
    case dacapoAlCoda           // !D.C.al Coda!
    case dalsegno               // !D.S.!
    case dalsegnoAlFine         // !D.S.al Fine!
    case dalsegnoAlCoda         // !D.S.al Coda!

    // Breath / pause
    case breath                 // !breath!
    case caesura                // !caesura!

    // Beaming (abcm2ps extensions; not drawn as a sign)
    /// `!beambr1!` / `!beambr2!` on a note: the beam group's beams below the first `n` stop
    /// before this note and start again on it, while the first `n` run through.  Only
    /// valid on a note or chord; see ``Note/beamBreak``.
    case beamBreak(Int)         // !beambr1! / !beambr2!

    // Forward compatibility — any !name! not in this table, preserved verbatim
    case unknown(String)
}

extension Decoration {
    /// The beams a list of decorations lets run through a beam break: the fewest any
    /// `.beamBreak` in it names, since `!beambr1!` breaks everything `!beambr2!` does.
    static func beamBreak(in decorations: [Decoration]) -> Int? {
        decorations.compactMap { if case .beamBreak(let n) = $0 { n } else { nil } }.min()
    }
}
