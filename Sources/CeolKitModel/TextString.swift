//
//  TextString.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct TextString: Hashable, Codable, Sendable {
    public let value: String        // Unicode string, ABC escapes fully resolved
    public let source: SourceRange
}
