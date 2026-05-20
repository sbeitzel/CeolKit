//
//  TuneMetadata.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct TuneMetadata {
    public let composer: TextString?
    public let origin: [String]          // O: semicolon-split; empty if absent
    public let area: TextString?         // A: — deprecated but preserved
    public let book: TextString?
    public let discography: TextString?
    public let fileURL: URL?
    public let group: TextString?
    public let history: [TextString]     // H: continuations become separate entries
    public let notes: TextString?
    public let source: TextString?
    public let rhythm: TextString?
    public let transcription: TextString?
}
