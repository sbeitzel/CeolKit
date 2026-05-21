import CeolKitModel

enum Token {
    // Accidentals
    case sharp                                               // ^
    case doubleSharp                                         // ^^
    case flat                                                // _
    case doubleFlat                                          // __
    case natural                                             // =
    case microtonalAccidental(sign: Int, numerator: Int, denominator: Int)

    // Pitch & octave
    case pitchLetter(Character)   // A–G or a–g
    case octaveUp                 // '
    case octaveDown               // ,

    // Duration
    case integer(Int)
    case slash                    // /

    // Bar lines
    case barSingle                // |
    case barDouble                // ||
    case barFinal                 // |]
    case barSectionStart          // [|
    case barRepeatStart           // |:
    case barRepeatEnd             // :|
    case barRepeatBoth            // ::
    case endingNumber([Int])      // |1  |2  [1  [2  [1-3

    // Brackets / parens / braces
    case leftBracket              // [
    case rightBracket             // ]
    case leftParen                // (
    case rightParen               // )
    case leftBrace                // {
    case rightBrace               // }
    case leftBraceSlash           // {/

    // Rhythm / articulation
    case tie                      // -
    case brokenRight              // >
    case brokenLeft               // <

    // Decorations
    case decorationOpen           // !  (first one opens)
    case decorationClose          // !  (second one closes)
    case shortDecoration(Character)   // . ~ H L M O P S T u v

    // Structural
    case space                    // whitespace run
    case backslash                // \

    // Chord/annotation
    case quotedString(String)     // "..."

    // Inline field
    case inlineField(code: Character, payload: String)

    // Rests
    case restNormal               // z
    case restInvisible            // x
    case restFullMeasure          // Z
    case restFullMeasureInvisible // X

    // Tuplet
    case tupletSpec(p: Int, q: Int?, r: Int?)

    // Unknown
    case unknown(Character)
}
