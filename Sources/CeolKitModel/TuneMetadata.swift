//
//  TuneMetadata.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct TuneMetadata: Sendable {
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

    public init(
        composer: TextString?,
        origin: [String],
        area: TextString?,
        book: TextString?,
        discography: TextString?,
        fileURL: URL?,
        group: TextString?,
        history: [TextString],
        notes: TextString?,
        source: TextString?,
        rhythm: TextString?,
        transcription: TextString?
    ) {
        self.composer = composer
        self.origin = origin
        self.area = area
        self.book = book
        self.discography = discography
        self.fileURL = fileURL
        self.group = group
        self.history = history
        self.notes = notes
        self.source = source
        self.rhythm = rhythm
        self.transcription = transcription
    }
}
