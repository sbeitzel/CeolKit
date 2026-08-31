//
//  VoiceProperties.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct VoiceProperties: Hashable, Sendable {
    public let clef: ClefSpec
    public let transposition: Transposition
    public let staffProperties: StaffProperties
    public let name: String?             // nm= — printed at start of first system
    public let subname: String?          // snm= — printed at subsequent systems
    public let stemDirection: StemDirection
    /// `middle=` — the pitch drawn on the middle staff line, or `nil` where the clef's own
    /// answer stands.
    ///
    /// A pitch rather than a pitch class because the middle line names one octave and not
    /// another: `middle=B` puts B4 there, which is where a treble clef already has it, and
    /// `middle=d` puts D5 there, which is a sixth higher.  Without the octave the value
    /// cannot say which.
    public let middleNote: Pitch?

    public init(
        clef: ClefSpec,
        transposition: Transposition,
        staffProperties: StaffProperties,
        name: String?,
        subname: String?,
        stemDirection: StemDirection,
        middleNote: Pitch?
    ) {
        self.clef = clef
        self.transposition = transposition
        self.staffProperties = staffProperties
        self.name = name
        self.subname = subname
        self.stemDirection = stemDirection
        self.middleNote = middleNote
    }
}
