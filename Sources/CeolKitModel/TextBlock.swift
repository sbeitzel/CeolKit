//
//  TextBlock.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct TextBlock: Sendable {
    public let content: String
    public let source: SourceRange

    public init(content: String, source: SourceRange) {
        self.content = content
        self.source = source
    }
}
