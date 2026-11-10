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
public enum Decoration: Hashable, Codable, Sendable {

    // Dynamics
    case pppp                   // !pppp!
    case ppp                    // !ppp!
    case pp                     // !pp!
    case p                      // !p!
    case mp                     // !mp!
    case mf                     // !mf!
    case f                      // !f!
    case ff                     // !ff!
    case fff                    // !fff!
    case ffff                   // !ffff!
    case sfz                    // !sfz!

    // Articulations
    case staccato               // !staccato! / .
    case staccatissimo          // !staccatissimo! / !wedge!
    case tenuto                 // !tenuto!
    case accent                 // !>! / !accent! / !emphasis! / L
    case strongAccent           // !^! / !marcato!  (marcato)
    case arpeggio               // !arpeggio!

    // Ornaments
    case trill                  // !trill! / T
    case trillStart             // !trill(!
    case trillEnd               // !trill)!
    case mordent                // !mordent! / !lowermordent! / M
    case pralltriller           // !pralltriller! / !uppermordent! / P
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
    case plus                   // !+! / !plus!  (left-hand pizzicato / stopped horn)
    case fingering(Int)         // !0! … !5!

    // Hairpins (single-event anchors)
    case crescendoStart         // !<(! / !crescendo(!
    case crescendoEnd           // !<)! / !crescendo)!
    case decrescendoStart       // !>(! / !diminuendo(!
    case decrescendoEnd         // !>)! / !diminuendo)!

    // Navigation / repeat signs
    case segno                  // !segno! / S
    case coda                   // !coda! / O
    case fine                   // !fine!
    case dacapo                 // !D.C.!
    case dacapoAlFine           // !D.C.alfine!
    case dacapoAlCoda           // !D.C.alcoda!
    case dalsegno               // !D.S.!
    case dalsegnoAlFine         // !D.S.alfine!
    case dalsegnoAlCoda         // !D.S.alcoda!
    /// `!dacapo!`: the words "Da Capo" in full, where ``dacapo`` is the letters "D.C.".
    case dacapoWords            // !dacapo!
    /// `!dacoda!`: the word "Da" followed by a coda sign.
    case dacoda                 // !dacoda!

    // Breath / pause
    case breath                 // !breath!
    case caesura                // !caesura!
    /// `!shortphrase!`: a short vertical line on the upper part of the staff.
    case shortPhrase            // !shortphrase!
    /// `!mediumphrase!`: the phrase line, down to the middle line.
    case mediumPhrase           // !mediumphrase!
    /// `!longphrase!`: the phrase line, three quarters of the way down the staff.
    case longPhrase             // !longphrase!

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

extension Decoration {
    /// A sign written in front of a bar line is drawn on it, not carried to the next note:
    /// the segno and coda, the D.C./D.S./Fine instructions, the fermata (a pause over the
    /// bar line), and the marks that stand between two notes — breath, caesura and phrase
    /// marks.
    public var isDrawnOnBarLine: Bool {
        switch self {
        case .segno, .coda, .fermata, .fine, .dacapo, .dacapoAlFine, .dacapoAlCoda, .dalsegno,
             .dalsegnoAlFine, .dalsegnoAlCoda, .dacapoWords, .dacoda,
             .breath, .caesura, .shortPhrase, .mediumPhrase, .longPhrase:
            return true
        default:
            return false
        }
    }
}
