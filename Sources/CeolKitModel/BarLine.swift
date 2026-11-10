//
//  BarLine.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct BarLine: Hashable, Codable, Sendable {
    public let kind: BarLineKind
    /// The signs written in front of the bar line that are drawn on it rather than on the
    /// next note: the segno and coda, the D.C./D.S./Fine instructions, the fermata, and the
    /// breath, caesura and phrase marks (issue #264).  `!segno!|` puts its segno here.
    public let decorations: [Decoration]
    public let source: SourceRange

    public init(kind: BarLineKind, decorations: [Decoration] = [], source: SourceRange) {
        self.kind = kind
        self.decorations = decorations
        self.source = source
    }
}

public enum BarLineKind: Hashable, Codable, Sendable {
    case single          // |   — ordinary bar line
    case double          // ||  — double thin (often signals section end)
    case final           // |]  — thin + thick (end of piece)
    case start           // [|  — thick + thin (start of section)
    case dotted          // .|  — dotted (optional/editorial)
    case repeatEnd       // :|  — repeat from nearest |: or start
    case repeatStart     // |:  — begin repeat section
    case repeatBoth      // ::  — end one repeat, start another
    case sectionRepeatStart  // [|:  — thick + thin + start-repeat (compound)
    case repeatEndSection    // :|]  — end-repeat + thin + thick (compound)
}
