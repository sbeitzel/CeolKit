import CeolKitModel

/// Reduces a fraction to lowest terms.
///
/// Shared by the semantic pass and the body context: both build durations, and each had
/// grown its own identical private copy of this and of `gcd`.
func reducedFraction(numerator: Int, denominator: Int) -> Fraction {
    guard numerator != 0 else { return Fraction(numerator: 0, denominator: 1) }
    let g = gcd(abs(numerator), abs(denominator))
    return Fraction(numerator: numerator / g, denominator: denominator / g)
}

private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
