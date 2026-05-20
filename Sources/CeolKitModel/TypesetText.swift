//
//  TypesetText.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct TypesetText {
    public let content: TextString          // expanded escapes, charset-decoded
    public let alignment: TextAlignment     // .left / .center / .right (from %%center, %%right, etc.)
    public let source: SourceRange
}
