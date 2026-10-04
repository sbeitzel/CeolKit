import CeolKitModel

extension KeySignature {
    /// This `K:` with what it left unsaid filled in from what is already in force, so the
    /// domain model only ever carries a decided key and clef.
    ///
    /// A `K:` that names no key (`K:bass`, `K:clef=bass`, an empty `K:`) keeps the key in
    /// force — abcm2ps keeps D major's sharps across `K:D` … `K:bass` — and, where nothing is
    /// in force, is `K:none` (§3.1.14).  One that states no clef keeps the clef in force.
    /// Everything the field does state is its own.
    ///
    /// - Parameters:
    ///   - inForce: the key standing where the field is met, or `nil` for none (the first
    ///     `K:` of the tune header).
    ///   - clef: the clef standing where the field is met, or `nil` for none.
    func resolved(against inForce: KeySignature?, clef clefInForce: ClefSpec?) -> KeySignature {
        guard !statesKey || !statesClef else { return self }
        let keyFrom = statesKey ? self : inForce
        return KeySignature(
            tonic: keyFrom?.tonic,
            mode: keyFrom?.mode ?? .none,
            modifications: statesKey || modifications.isEmpty
                ? (keyFrom?.modifications ?? []) : modifications,
            explicit: (keyFrom?.explicit ?? false) || explicit,
            clef: statesClef ? clef : (clefInForce ?? clef),
            transposition: transposition,
            staffProperties: staffProperties,
            source: source
        )
    }
}
