//
//  Spacer.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct Spacer: Sendable {
    public let width: Int                // 1 for bare y, explicit number for y2, y4, etc.
    public let source: SourceRange

    public init(width: Int, source: SourceRange) {
        self.width = width
        self.source = source
    }
}
