import Foundation
import CeolKitModel

public enum UnknownExtensionPolicy: Sendable {
    case preserve
    case warn
    case drop
}

public struct ParseOptions: Sendable {
    public var dialectOverride: Dialect?
    public var maxDiagnostics: Int
    public var unknownExtensionPolicy: UnknownExtensionPolicy
    public var strictRecovery: Bool

    public init(
        dialectOverride: Dialect? = nil,
        maxDiagnostics: Int = .max,
        unknownExtensionPolicy: UnknownExtensionPolicy = .warn,
        strictRecovery: Bool = false
    ) {
        self.dialectOverride = dialectOverride
        self.maxDiagnostics = maxDiagnostics
        self.unknownExtensionPolicy = unknownExtensionPolicy
        self.strictRecovery = strictRecovery
    }

    public static let `default` = ParseOptions()
}

public struct ParseResult {
    public let score: Score
    public let diagnostics: [Diagnostic]
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    public init(score: Score, diagnostics: [Diagnostic]) {
        self.score = score
        self.diagnostics = diagnostics
    }
}

public protocol ABCParser {
    func parse(_ source: String, options: ParseOptions) -> ParseResult
    func parse(_ source: String, options: ParseOptions, dialectHint: Dialect?) -> ParseResult
}

public struct CeolKitParser: ABCParser {
    public typealias FileResolver = @Sendable (URL) throws -> Data

    let baseDir: URL?
    let fileResolver: FileResolver?

    public init(for baseDir: URL? = nil, fileResolver: FileResolver? = nil) {
        self.baseDir = baseDir
        self.fileResolver = fileResolver
    }

    public func parse(_ source: String, options: ParseOptions) -> ParseResult {
        parse(source, options: options, dialectHint: nil)
    }

    public func parse(_ source: String, options: ParseOptions, dialectHint: Dialect?) -> ParseResult {
        let src = Source(content: source, fileName: nil)
        let classifier = LineClassifier(source: src, dialectHint: dialectHint)
        let lines = classifier.classify()
        let expander = IncludeExpander(baseDir: baseDir, options: options, dialectHint: dialectHint, fileResolver: fileResolver)
        let (expandedLines, includeDiags) = expander.expand(lines)
        let builder = ABCFileBuilder(lines: expandedLines, options: options, preDiagnostics: includeDiags)
        let abcFile = builder.build()
        let pass = SemanticPass(file: abcFile, options: options, dialectHint: dialectHint)
        let (score, diagnostics) = pass.build()
        return ParseResult(score: score, diagnostics: diagnostics)
    }
}

public extension CeolKitParser {
    static let defaultFileResolver: FileResolver = {
        return { url in
            return try Data(contentsOf: url)
        }
    }()
}
