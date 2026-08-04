//
//  Options.swift
//  ckprobe
//
//  Hand-rolled argument parsing.  Adding swift-argument-parser would put a new
//  package-level dependency in Package.swift, which every SPM consumer that resolves
//  the graph through Tuist would then have to mirror in its own manifest.  Not worth
//  it for six flags.
//

import Foundation

struct Options {
    var file: URL
    /// Override `%%ceolkit:scale` before rendering.
    var scale: Double?
    /// Render once per factor and print a systems/pages table instead of a full report.
    var sweep: [Double]?
    /// Force `%%ceolkit:justifylast false` so reported widths are natural, not stretched.
    var natural: Bool = false
    /// Directory to write `page0.svg`, `page1.svg`, … into.
    var outputDirectory: URL?
    var json: Bool = false

    static let usage = """
        usage: ckprobe <file.abc> [options]

        Parses and renders an ABC file, then reports the layout geometry of the result.
        Includes (I:abc-include) resolve against the file's own directory.

        Options:
          --scale <factor>      Override %%ceolkit:scale before rendering.
          --sweep <f,f,…>       Render at each factor; print a systems/pages table.
          --natural             Force %%ceolkit:justifylast false, so system widths
                                are reported unstretched.
          --out <dir>           Write page0.svg, page1.svg, … into <dir>.
          --json                Emit JSON instead of the text report.
          -h, --help            Show this message.

        To look at a page:
          ckprobe tune.abc --out /tmp/out
          rsvg-convert -w 1500 /tmp/out/page0.svg -o /tmp/page0.png
        """

    /// Thrown for anything that should print usage and exit non-zero.
    struct ParseError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var positional: [String] = []
        var scale: Double?
        var sweep: [Double]?
        var natural = false
        var outputDirectory: URL?
        var json = false

        /// Consumes the value that follows a flag.
        func value(after index: inout Int, of flag: String, in args: [String]) throws -> String {
            index += 1
            guard index < args.count else {
                throw ParseError(description: "\(flag) requires a value")
            }
            return args[index]
        }

        var i = 0
        while i < arguments.count {
            let argument = arguments[i]
            switch argument {
            case "-h", "--help":
                throw ParseError(description: "")

            case "--scale":
                let raw = try value(after: &i, of: "--scale", in: arguments)
                guard let factor = Double(raw), factor > 0 else {
                    throw ParseError(description: "--scale expects a positive number, got '\(raw)'")
                }
                scale = factor

            case "--sweep":
                let raw = try value(after: &i, of: "--sweep", in: arguments)
                let factors = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard !factors.isEmpty, factors.allSatisfy({ ($0 ?? 0) > 0 }) else {
                    throw ParseError(description: "--sweep expects a comma-separated list of positive numbers, got '\(raw)'")
                }
                sweep = factors.compactMap { $0 }

            case "--natural":
                natural = true

            case "--out":
                outputDirectory = URL(fileURLWithPath: try value(after: &i, of: "--out", in: arguments))

            case "--json":
                json = true

            default:
                guard !argument.hasPrefix("-") else {
                    throw ParseError(description: "unknown option '\(argument)'")
                }
                positional.append(argument)
            }
            i += 1
        }

        guard positional.count == 1 else {
            throw ParseError(description: positional.isEmpty
                ? "expected an ABC file"
                : "expected exactly one ABC file, got \(positional.count)")
        }

        return Options(
            file: URL(fileURLWithPath: positional[0]),
            scale: scale,
            sweep: sweep,
            natural: natural,
            outputDirectory: outputDirectory,
            json: json
        )
    }
}
