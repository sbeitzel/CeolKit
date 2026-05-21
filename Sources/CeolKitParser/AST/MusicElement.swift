import CeolKitModel

enum MusicElement {
    case note(NoteToken)
    case chord([NoteToken], source: SourceRange)
    case rest(kind: RestKind, duration: DurationToken, source: SourceRange)
    case barLine(kind: BarLineKind, source: SourceRange)
    case endingNumber([Int], source: SourceRange)
    case tupletStart(p: Int, q: Int?, r: Int?, source: SourceRange)
    case graceStart(acciaccatura: Bool, source: SourceRange)
    case graceEnd(source: SourceRange)
    case slurOpen(source: SourceRange)
    case slurClose(source: SourceRange)
    case decoration(DecorationToken, source: SourceRange)
    case inlineField(InformationField, source: SourceRange)
    case space(source: SourceRange)
    case brokenRhythm(count: Int, direction: BrokenDirection, source: SourceRange)
    case chordSymbol(String, source: SourceRange)
    case annotation(AnnotationPosition, String, source: SourceRange)
    case unknown(Character, source: SourceRange)
}

struct NoteToken {
    let accidental: AccidentalToken?
    let pitchLetter: Character    // A–G or a–g; case encodes the base octave
    let octaveMarks: Int          // net shift: +N for N primes, -N for N commas
    let duration: DurationToken
    let tie: Bool
    let source: SourceRange
}

struct DurationToken {
    let numerator: Int    // explicit; default 1
    let denominator: Int  // explicit; default 1
}

enum AccidentalToken {
    case sharp
    case doubleSharp
    case flat
    case doubleFlat
    case natural
    case microtonal(sign: Int, numerator: Int, denominator: Int)  // unreduced; semantic pass reduces
}

enum DecorationToken {
    case longForm(String)    // text between ! … !
    case shortForm(Character)
}

enum BrokenDirection {
    case right  // >
    case left   // <
}
