//
//  TuneMetadata.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// The string-type information fields of a tune header.
///
/// Every field is an ordered list, filled in source order and empty when the field is absent:
/// ABC v2.2 §3 treats a repeated string field as additional information rather than a
/// replacement, so a tune with three `N:` lines has three notes (issue #188).  Joining them
/// for display — with `;`, or one per line as §6.1.3 asks of composers — is the renderer's
/// choice, not the model's.
public struct TuneMetadata: Sendable {
    public let composer: [TextString]
    public let origin: [String]          // O: semicolon-split; empty if absent
    public let area: [TextString]        // A: — deprecated but preserved
    public let book: [TextString]
    public let discography: [TextString]
    public let fileURL: [URL]            // F: values that do not parse as a URL are dropped
    public let group: [TextString]
    public let history: [TextString]     // H: continuations become separate entries
    public let notes: [TextString]
    public let source: [TextString]
    public let rhythm: [TextString]
    public let transcription: [TextString]

    public init(
        composer: [TextString] = [],
        origin: [String] = [],
        area: [TextString] = [],
        book: [TextString] = [],
        discography: [TextString] = [],
        fileURL: [URL] = [],
        group: [TextString] = [],
        history: [TextString] = [],
        notes: [TextString] = [],
        source: [TextString] = [],
        rhythm: [TextString] = [],
        transcription: [TextString] = []
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
