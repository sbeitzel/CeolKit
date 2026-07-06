import Foundation
import CeolKitModel

struct IncludeExpander {
    let baseDir: URL?
    let options: ParseOptions
    let dialectHint: Dialect?
    let fileResolver: CeolKitParser.FileResolver?

    func expand(_ lines: [LogicalLine], seen: Set<URL> = []) -> ([LogicalLine], [Diagnostic]) {
        var result: [LogicalLine] = []
        var diagnostics: [Diagnostic] = []

        for line in lines {
            guard case .informationField(let code, let payload, let source) = line,
                  code == "I" else {
                result.append(line)
                continue
            }

            let trimmed = payload.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("abc-include") else {
                result.append(line)
                continue
            }

            let filename = String(trimmed.dropFirst("abc-include".count))
                .trimmingCharacters(in: .whitespaces)

            guard !filename.isEmpty else {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: .malformedFieldPayload,
                    message: "I:abc-include requires a filename",
                    source: source
                ))
                continue
            }

            guard let baseDir else {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: .includeNoBaseDirectory,
                    message: "I:abc-include '\(filename)' ignored — parser has no base directory",
                    source: source
                ))
                continue
            }

            let resolvedURL = baseDir.appendingPathComponent(filename).standardized

            guard !seen.contains(resolvedURL) else {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: .circularInclude,
                    message: "Circular include of '\(resolvedURL.path)'",
                    source: source
                ))
                continue
            }

            let data: Data
            do {
                if let fileResolver {
                    data = try fileResolver(resolvedURL)
                } else {
                    diagnostics.append(Diagnostic(
                        severity: .info,
                        code: .usingDefaultFileResolver,
                        message: "No fileResolver provided; reading '\(resolvedURL.path)' via Data(contentsOf:)",
                        source: source
                    ))
                    data = try CeolKitParser.defaultFileResolver(resolvedURL)
                }
            } catch {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: .includeFileNotFound,
                    message: "Cannot read include file '\(resolvedURL.path)': \(error.localizedDescription)",
                    source: source
                ))
                continue
            }

            guard let text = String(data: data, encoding: .utf8) else {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: .includeFileNotFound,
                    message: "Include file '\(resolvedURL.path)' is not valid UTF-8",
                    source: source
                ))
                continue
            }

            let includedSource = Source(content: text, fileName: resolvedURL.path)
            let classifier = LineClassifier(source: includedSource, dialectHint: dialectHint)
            let includedLines = classifier.classify()
            let (expandedLines, expandedDiags) = expand(includedLines, seen: seen.union([resolvedURL]))
            // Strip trailing empty lines: a file-ending newline produces a spurious .empty
            // that would prematurely flush the parent tune in ABCFileBuilder.
            var trimmedLines = expandedLines
            while case .empty? = trimmedLines.last { trimmedLines.removeLast() }
            result.append(contentsOf: trimmedLines)
            diagnostics.append(contentsOf: expandedDiags)
        }

        return (result, diagnostics)
    }
}
