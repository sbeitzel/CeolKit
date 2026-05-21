import CeolKitModel

enum LogicalLine {
    case empty(source: SourceRange)
    case comment(text: String, source: SourceRange)
    case versionLine(version: String, source: SourceRange)
    case directive(name: String, payload: String, source: SourceRange)
    case informationField(code: Character, payload: String, source: SourceRange)
    case musicLine(text: String, source: SourceRange)
    case freeText(text: String, source: SourceRange)

    var source: SourceRange {
        switch self {
        case .empty(let s): return s
        case .comment(_, let s): return s
        case .versionLine(_, let s): return s
        case .directive(_, _, let s): return s
        case .informationField(_, _, let s): return s
        case .musicLine(_, let s): return s
        case .freeText(_, let s): return s
        }
    }
}
