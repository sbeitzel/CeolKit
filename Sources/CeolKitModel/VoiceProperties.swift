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
    public let middleNote: PitchClass?   // middle= — pitch on the middle staff line; nil = default

    public init(
        clef: ClefSpec,
        transposition: Transposition,
        staffProperties: StaffProperties,
        name: String?,
        subname: String?,
        stemDirection: StemDirection,
        middleNote: PitchClass?
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
