//
//  SourceRange.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct SourceRange: Hashable, Identifiable, Sendable, Codable {
    public var id: String {
        let fileStr = file?.path ?? "<null>"
        return "\(fileStr):\(line):\(column):\(byteOffset):\(length)"
    }
    public let file: URL?
    public let byteOffset: Int
    public let length: Int
    public let line: Int
    public let column: Int

    public init(file: URL?, byteOffset: Int, length: Int, line: Int, column: Int) {
        self.file = file
        self.byteOffset = byteOffset
        self.length = length
        self.line = line
        self.column = column
    }
}
