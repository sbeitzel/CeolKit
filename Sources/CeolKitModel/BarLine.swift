//
//  BarLine.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct BarLine: Hashable, Codable, Sendable {
    public let kind: BarLineKind
    public let source: SourceRange

    public init(kind: BarLineKind, source: SourceRange) {
        self.kind = kind
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
}
