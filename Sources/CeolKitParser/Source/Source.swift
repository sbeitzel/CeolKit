import Foundation
import CeolKitModel

struct Source {
    let content: String
    let fileName: String?

    private let normalized: String
    private let lineData: [(lineNumber: Int, text: Substring, byteOffset: Int)]

    init(content: String, fileName: String?) {
        self.content = content
        self.fileName = fileName
        let norm = content.replacing(/\r\n/, with: "\n")
        self.normalized = norm
        self.lineData = Self.buildLines(norm)
    }

    private static func buildLines(_ text: String) -> [(lineNumber: Int, text: Substring, byteOffset: Int)] {
        var result: [(lineNumber: Int, text: Substring, byteOffset: Int)] = []
        var lineNumber = 1
        var byteOffset = 0
        var lineStart = text.startIndex
        var lineStartByteOffset = 0
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]
            if ch == "\n" {
                result.append((lineNumber: lineNumber, text: text[lineStart..<i], byteOffset: lineStartByteOffset))
                lineNumber += 1
                let next = text.index(after: i)
                byteOffset += 1  // \n is always 1 byte in UTF-8
                lineStartByteOffset = byteOffset
                lineStart = next
                i = next
            } else {
                byteOffset += ch.utf8.count
                i = text.index(after: i)
            }
        }

        result.append((lineNumber: lineNumber, text: text[lineStart...], byteOffset: lineStartByteOffset))
        return result
    }

    func lines() -> [(lineNumber: Int, text: Substring, byteOffset: Int)] {
        lineData
    }

    func range(line: Int, column: Int, length: Int) -> SourceRange {
        let lineIndex = line - 1
        let lineByteOffset = lineIndex < lineData.count ? lineData[lineIndex].byteOffset : 0
        let fileURL = fileName.flatMap { URL(fileURLWithPath: $0) }
        return SourceRange(
            file: fileURL,
            byteOffset: lineByteOffset + (column - 1),
            length: length,
            line: line,
            column: column
        )
    }
}
