import CeolKitModel

enum KeyFieldParser {
    static func parse(payload: String, source: SourceRange) -> (KeySignature, [Diagnostic]) {
        let t = payload.trimmingCharacters(in: .whitespaces)

        var rest = t[...]
        let tonic: PitchClass?
        let mode: Mode
        var statesKey = true

        // The keys named by a word rather than by a tonic.  The word is consumed like any
        // other, not matched against the whole payload: `K:none clef=bass` states a clef the
        // same way `K:C clef=bass` does, and the options after it are read the same way too.
        let firstWord = String(rest.prefix(while: { !$0.isWhitespace }))
        if let specialMode = specialKeyMode(firstWord) {
            tonic = nil
            mode = specialMode
            rest = rest.dropFirst(firstWord.count)
        } else if let first = rest.first, "ABCDEFG".contains(first), let step = diatonicStep(from: first) {
            rest = rest.dropFirst()

            // Optional tonic alteration: 'b' = flat, '#' = sharp
            var tonicAlt = Alteration(numerator: 0, denominator: 1)
            if rest.first == "b" {
                tonicAlt = Alteration(numerator: -1, denominator: 1)
                rest = rest.dropFirst()
            } else if rest.first == "#" {
                tonicAlt = Alteration(numerator: 1, denominator: 1)
                rest = rest.dropFirst()
            }
            tonic = PitchClass(step: step, alteration: tonicAlt)

            // Skip whitespace before mode keyword
            rest = Substring(rest.drop(while: { $0.isWhitespace }))

            // Mode keyword
            let (parsedMode, modeLen) = parseMode(from: rest)
            if modeLen > 0 { rest = rest.dropFirst(modeLen) }
            mode = parsedMode
        } else {
            // No key at all, only options: `K:clef=bass`, `K:bass` (§4.6 lets a named clef
            // drop its `clef=`), or an empty `K:` (§3.1.14).  The whole payload is options,
            // and what key is in force is left to the semantic pass to decide.
            tonic = nil
            mode = .none
            statesKey = false
        }
        rest = Substring(rest.drop(while: { $0.isWhitespace }))

        // Remaining options (space-separated tokens)
        var clef: Clef = .treble
        var octaveShift = 0
        var explicit = false
        var modifications: [KeyModification] = []
        var staffLines = 5
        var octave: Int? = nil
        var statesClef = false
        var unrecognised = 0

        let tokens = String(rest).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for tok in tokens {
            if tok == "exp" {
                explicit = true
            } else if tok.hasPrefix("clef=") {
                let (c, s) = parseClefSpec(String(tok.dropFirst(5)))
                clef = c; octaveShift = s; statesClef = true
            } else if tok.hasPrefix("stafflines=") {
                if let n = Int(tok.dropFirst("stafflines=".count)) { staffLines = n }
            } else if tok.hasPrefix("octave=") {
                // §4.6: shifts the music of the voice the field applies to by whole octaves.
                if let n = Int(tok.dropFirst("octave=".count)) { octave = n }
            } else if tok.hasPrefix("middle=") || tok.hasPrefix("oct=") {
                // ignored in v0.1
            } else if let (c, s) = tryClefToken(tok) {
                clef = c; octaveShift = s; statesClef = true
            } else if let mod = parseModification(tok) {
                modifications.append(mod)
            } else {
                // Silently ignored after a key; see below for a `K:` with no key.
                unrecognised += 1
            }
        }

        // A payload with no key and nothing else recognisable in it is not options without
        // a key — it is a key nobody could read, so it is still reported.  It changes nothing:
        // like any other `K:` without a key, it leaves the semantic pass the key in force.
        if !statesKey, unrecognised > 0, unrecognised == tokens.count {
            return (
                unreadableKey(source: source),
                [malformed("Key must start with A–G, 'none', 'HP', or 'Hp': '\(payload)'", source)]
            )
        }

        let key = KeySignature(
            tonic: tonic,
            mode: mode,
            modifications: modifications,
            explicit: explicit,
            clef: ClefSpec(clef: clef, octaveShift: octaveShift),
            transposition: octave.map { Transposition(semitones: 0, octave: $0, statesOctave: true) }
                ?? .none,
            staffProperties: StaffProperties(staffLines: staffLines),
            source: source,
            statesKey: statesKey,
            statesClef: statesClef
        )
        return (key, [])
    }

    // MARK: - Mode parsing

    /// The three keys the standard names by a word: `none`, and the two Highland pipe keys.
    ///
    /// `none` is matched without regard to case, `HP` and `Hp` with it — they are different
    /// keys, so their case is the only thing telling them apart.
    private static func specialKeyMode(_ word: String) -> Mode? {
        if word.lowercased() == "none" { return Mode.none }
        if word == "HP" { return .highlandPipes }
        if word == "Hp" { return .highlandPipesNoSignature }
        return nil
    }

    private static func parseMode(from rest: Substring) -> (Mode, Int) {
        // Read a run of letters = the mode word
        var wordLen = 0
        var i = rest.startIndex
        while i < rest.endIndex, rest[i].isLetter {
            wordLen += 1
            i = rest.index(after: i)
        }
        guard wordLen > 0 else { return (.major, 0) }
        let word = String(rest.prefix(wordLen)).lowercased()

        // "m" alone → minor; otherwise need ≥3 chars
        if word == "m" { return (.minor, 1) }
        if wordLen < 3  { return (.major, 0) }

        if word.hasPrefix("maj") || word.hasPrefix("ion") { return (.major, wordLen) }
        if word.hasPrefix("min") { return (.minor, wordLen) }
        if word.hasPrefix("aeo") { return (.aeolian, wordLen) }
        if word.hasPrefix("dor") { return (.dorian, wordLen) }
        if word.hasPrefix("phr") { return (.phrygian, wordLen) }
        if word.hasPrefix("lyd") { return (.lydian, wordLen) }
        if word.hasPrefix("mix") { return (.mixolydian, wordLen) }
        if word.hasPrefix("loc") { return (.locrian, wordLen) }

        // Not a recognised mode keyword — treat as major, don't consume
        return (.major, 0)
    }

    // MARK: - Clef helpers

    private static func tryClefToken(_ tok: String) -> (Clef, Int)? {
        let (name, shift) = splitClefShift(tok)
        guard clefNames.contains(name.lowercased()) else { return nil }
        return (clef(fromName: name), shift)
    }

    static func parseClefSpec(_ s: String) -> (Clef, Int) {
        let (name, shift) = splitClefShift(s)
        return (clef(fromName: name), shift)
    }

    private static func splitClefShift(_ s: String) -> (String, Int) {
        if let idx = s.lastIndex(of: "+") {
            let suffix = String(s[s.index(after: idx)...])
            if let n = Int(suffix) { return (String(s[..<idx]), n) }
        }
        if let idx = s.lastIndex(of: "-") {
            let suffix = String(s[s.index(after: idx)...])
            if let n = Int(suffix) { return (String(s[..<idx]), -n) }
        }
        return (s, 0)
    }

    private static let clefNames: Set<String> = [
        "treble", "bass", "baritone", "bass3", "alto", "tenor",
        "soprano", "mezzosoprano", "perc", "percussion", "none"
    ]

    static func clef(fromName name: String) -> Clef {
        switch name.lowercased() {
        case "treble":                  return .treble
        case "bass":                    return .bass
        case "baritone", "bass3":       return .baritone
        case "alto":                    return .alto
        case "tenor":                   return .tenor
        case "soprano":                 return .soprano
        case "mezzosoprano":            return .mezzoSoprano
        case "perc", "percussion":      return .percussion
        case "none":                    return .none
        default:                        return .treble
        }
    }

    // MARK: - Modification parsing (^f _b =e ^^f __b ^3/2f ...)

    private static func parseModification(_ tok: String) -> KeyModification? {
        var s = tok[...]
        var altNum = 0
        var altDen = 1

        if s.hasPrefix("^^") {
            altNum = 2; altDen = 1; s = s.dropFirst(2)
        } else if s.hasPrefix("^") {
            s = s.dropFirst()
            if let n = scanInt(&s), s.first == "/" {
                s = s.dropFirst()
                altDen = scanInt(&s) ?? 1; altNum = n
            } else {
                altNum = 1; altDen = 1
            }
        } else if s.hasPrefix("__") {
            altNum = -2; altDen = 1; s = s.dropFirst(2)
        } else if s.hasPrefix("_") {
            s = s.dropFirst()
            if let n = scanInt(&s), s.first == "/" {
                s = s.dropFirst()
                altDen = scanInt(&s) ?? 1; altNum = -n
            } else {
                altNum = -1; altDen = 1
            }
        } else if s.hasPrefix("=") {
            altNum = 0; altDen = 1; s = s.dropFirst()
        } else {
            return nil
        }

        guard let letter = s.first, letter.isLetter,
              let step = diatonicStep(from: Character(letter.uppercased())) else { return nil }

        return KeyModification(step: step, alteration: Alteration(numerator: altNum, denominator: altDen))
    }

    private static func scanInt(_ s: inout Substring) -> Int? {
        guard s.first?.isNumber == true else { return nil }
        var val = 0
        while let c = s.first, c.isNumber, let d = c.wholeNumberValue {
            val = val * 10 + d; s = s.dropFirst()
        }
        return val
    }

    // MARK: - Factories

    private static func unreadableKey(source: SourceRange) -> KeySignature {
        KeySignature(
            tonic: nil,
            mode: .none,
            modifications: [],
            explicit: false,
            clef: ClefSpec(clef: .treble, octaveShift: 0),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: 5),
            source: source,
            statesKey: false,
            statesClef: false
        )
    }
}

// MARK: - Shared helpers (module-internal)

func diatonicStep(from ch: Character) -> DiatonicStep? {
    switch ch {
    case "C", "c": return .c
    case "D", "d": return .d
    case "E", "e": return .e
    case "F", "f": return .f
    case "G", "g": return .g
    case "A", "a": return .a
    case "B", "b": return .b
    default: return nil
    }
}

private func malformed(_ msg: String, _ source: SourceRange) -> Diagnostic {
    Diagnostic(severity: .warning, code: .malformedFieldPayload, message: msg,
               source: source, related: [], hint: nil)
}
