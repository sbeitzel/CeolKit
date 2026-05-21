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
public struct Alteration: Hashable, Sendable {
    public let numerator: Int
    public let denominator: Int            // > 0, post-reduction

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let sharp       = Alteration(numerator:  1, denominator: 1)
    public static let flat        = Alteration(numerator: -1, denominator: 1)
    public static let doubleSharp = Alteration(numerator:  2, denominator: 1)
    public static let doubleFlat  = Alteration(numerator: -2, denominator: 1)
    public static let natural     = Alteration(numerator:  0, denominator: 1)

    public static func reduced(numerator: Int, denominator: Int) -> Alteration {
        guard numerator != 0 else { return .natural }
        let d = denominator > 0 ? denominator : -denominator
        let sign = denominator < 0 ? -1 : 1
        let g = gcd(abs(numerator), d)
        return Alteration(numerator: sign * numerator / g, denominator: d / g)
    }
}

private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
