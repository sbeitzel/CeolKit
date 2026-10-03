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
        overriding(["ceolkit:\(name)"], with: "%%ceolkit:\(name) \(value)", in: source)
    }

    /// Returns `source` with every directive named in `names` replaced by `directive`, or
    /// with `directive` inserted before the first `X:` where none of them is written.
    static func overriding(_ names: [String], with directive: String,
                           in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        var replaced = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard trimmed.hasPrefix("%%") else { continue }
            let name = trimmed.dropFirst(2).prefix { !$0.isWhitespace }
            guard names.contains(String(name)) else { continue }
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
            // abcm2ps's `-s`: one `%%scale` in place of whichever spelling the file uses.
            result = overriding(["scale", "pagescale", "ceolkit:scale"],
                                with: "%%scale \(scale)", in: result)
        }
        if let graceSpacing = options.graceSpacing {
            result = overriding("gracenotespacing", with: String(graceSpacing), in: result)
        }
        if options.natural {
            result = overriding("justifylast", with: "false", in: result)
        }
        return result
    }
}
