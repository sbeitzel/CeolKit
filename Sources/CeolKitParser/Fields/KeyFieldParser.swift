import CeolKitModel

enum KeyFieldParser {
    static func parse(payload: String, source: SourceRange) -> (KeySignature, [Diagnostic]) {
        let t = payload.trimmingCharacters(in: .whitespaces)

        // Special cases
        if t.lowercased() == "none" {
            return (makeKey(tonic: nil, mode: Mode.none, source: source), [])
        }
        if t == "HP" {
            return (makeKey(tonic: nil, mode: .highlandPipes, source: source), [])
        }
        if t == "Hp" {
            return (makeKey(tonic: nil, mode: .highlandPipesNoSignature, source: source), [])
        }

        var rest = t[...]

        // Tonic letter (A–G)
        guard let first = rest.first, "ABCDEFG".contains(first),
              let step = diatonicStep(from: first) else {
            return (
                makeKey(tonic: nil, mode: .major, source: source),
                [malformed("Key must start with A–G, 'none', 'HP', or 'Hp': '\(payload)'", source)]
            )
        }
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
        let tonic = PitchClass(step: step, alteration: tonicAlt)

        // Skip whitespace before mode keyword
        rest = Substring(rest.drop(while: { $0.isWhitespace }))

        // Mode keyword
        let (mode, modeLen) = parseMode(from: rest)
        if modeLen > 0 { rest = rest.dropFirst(modeLen) }
        rest = Substring(rest.drop(while: { $0.isWhitespace }))

        // Remaining options (space-separated tokens)
        var clef: Clef = .treble
        var octaveShift = 0
        var explicit = false
        var modifications: [KeyModification] = []
        var staffLines = 5

        let tokens = String(rest).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        for tok in tokens {
            if tok == "exp" {
                explicit = true
            } else if tok.hasPrefix("clef=") {
                let (c, s) = parseClefSpec(String(tok.dropFirst(5)))
                clef = c; octaveShift = s
            } else if tok.hasPrefix("stafflines=") {
                if let n = Int(tok.dropFirst("stafflines=".count)) { staffLines = n }
            } else if tok.hasPrefix("middle=") || tok.hasPrefix("oct=") {
                // ignored in v0.1
            } else if let (c, s) = tryClefToken(tok) {
                clef = c; octaveShift = s
            } else if let mod = parseModification(tok) {
                modifications.append(mod)
            }
            // unknown tokens silently ignored
        }

        let key = KeySignature(
            tonic: tonic,
            mode: mode,
            modifications: modifications,
            explicit: explicit,
            clef: ClefSpec(clef: clef, octaveShift: octaveShift),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: staffLines, scale: nil),
            source: source
        )
        return (key, [])
    }

    // MARK: - Mode parsing

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

    private static func makeKey(tonic: PitchClass?, mode: Mode, source: SourceRange) -> KeySignature {
        KeySignature(
            tonic: tonic,
            mode: mode,
            modifications: [],
            explicit: false,
            clef: ClefSpec(clef: .treble, octaveShift: 0),
            transposition: .none,
            staffProperties: StaffProperties(staffLines: 5, scale: nil),
            source: source
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
