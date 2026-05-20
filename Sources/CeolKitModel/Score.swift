//
//  Score.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Score {
    public let source: SourceRange
    public let dialect: Dialect
    public let creator: String?                  // I:abc-creator
    public let charset: String?                  // I:abc-charset
    public let tunes: [Tune]
    public let freeText: [TextBlock]
    public let typesetText: [TypesetText]
    public let diagnostics: [Diagnostic]         // all issues from all stages
}
