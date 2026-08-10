//
//  SourceRewriter.swift
//  ckprobe
//
//  Applies command-line directive overrides to ABC source before it is parsed.
//

import Foundation

enum SourceRewriter {

    /// Returns `source` with `%%ceolkit:<name> <value>` in force for the whole file.
    ///
    /// An existing directive line is rewritten in place, which keeps every following
    /// line at its original number — the emitted scroll-sync anchors are reported
    /// against the source, so shifting line numbers would make the report lie.  Only
    /// when the directive is absent entirely is a line inserted, immediately before the
    /// first `X:`.  That position is the end of the file preamble: after any
    /// `I:abc-include`, so an override beats a value the include supplies, and still
    /// file-global, so the parser promotes it to every tune.
    static func overriding(_ name: String, with value: String, in source: String) -> String {
        let directive = "%%ceolkit:\(name) \(value)"
        var lines = source.components(separatedBy: "\n")
        var replaced = false

        for (index, line) in lines.enumerated()
        where line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("%%ceolkit:\(name)") {
            lines[index] = directive
            replaced = true
        }
        guard !replaced else { return lines.joined(separator: "\n") }

        let insertionPoint = lines.firstIndex { $0.hasPrefix("X:") } ?? lines.count
        lines.insert(directive, at: insertionPoint)
        return lines.joined(separator: "\n")
    }

    /// Applies every override implied by `options`.
    static func apply(_ options: Options, to source: String, scaleOverride: Double? = nil) -> String {
        var result = source
        if let scale = scaleOverride ?? options.scale {
            result = overriding("scale", with: String(scale), in: result)
        }
        if options.natural {
            result = overriding("justifylast", with: "false", in: result)
        }
        return result
    }
}
