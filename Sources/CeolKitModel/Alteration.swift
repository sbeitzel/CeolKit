//
//  Alteration.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

/// A semitone offset from the natural form of the diatonic step.
///
/// Stored as `numerator / denominator` (both `Int`) and *always* normalised so
/// that `denominator > 0` and `gcd(|numerator|, denominator) == 1`. This is
/// lossless: the `^k/n` written in ABC source survives unchanged into the
/// model and back out to the renderer's glyph table.
///
///   `^C`           -> Alteration(numerator:  1, denominator: 1)
///   `_C`           -> Alteration(numerator: -1, denominator: 1)
///   `^^C`          -> Alteration(numerator:  2, denominator: 1)
///   `__C`          -> Alteration(numerator: -2, denominator: 1)
///   `=C / natural` -> Alteration(numerator:  0, denominator: 1)
///   `^3/2C`        -> Alteration(numerator:  3, denominator: 2)  // three-quarter sharp
///   `_1/2C`        -> Alteration(numerator: -1, denominator: 2)  // quarter flat
///
/// Common values are provided as static members for ergonomics:
///   .natural, .sharp, .flat, .doubleSharp, .doubleFlat,
///   .quarterSharp, .quarterFlat, .threeQuarterSharp, .threeQuarterFlat
public struct Alteration: Hashable {
    public let numerator: Int
    public let denominator: Int            // > 0, post-reduction

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }
}
