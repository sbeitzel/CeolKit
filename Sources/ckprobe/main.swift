//
//  main.swift
//  ckprobe
//
//  A development probe for the SVG renderer: parse an ABC file, render it, and report
//  what came out — diagnostics, tune structure, and the geometry of every system on
//  every page.  Not shipped to consumers; see Package.swift.
//

import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
import CeolKitSVGRenderer
import Foundation

func fail(_ message: String, usage: Bool = false) -> Never {
    if !message.isEmpty {
        FileHandle.standardError.write(Data("ckprobe: \(message)\n".utf8))
    }
    if usage {
        FileHandle.standardError.write(Data((Options.usage + "\n").utf8))
    }
    exit(message.isEmpty ? 0 : 2)
}

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch let error as Options.ParseError {
    fail(error.description, usage: true)
} catch {
    fail("\(error)", usage: true)
}

guard let source = try? String(contentsOf: options.file, encoding: .utf8) else {
    fail("cannot read \(options.file.path)")
}

/// Parses with the file's own directory as the include base, so `I:abc-include` resolves
/// the way it does for a host application opening the same file.
func parse(_ abc: String) -> ParseResult {
    CeolKitParser(for: options.file.deletingLastPathComponent(),
                  fileResolver: CeolKitParser.defaultFileResolver)
        .parse(abc, options: .default)
}

let renderConfig = SVGRenderConfig(textRendering: options.textRendering)

func render(_ abc: String) throws -> [String] {
    try SVGRenderer(config: renderConfig).render(parse(abc).score)
}

// MARK: - Sweep mode

if let factors = options.sweep {
    print(Report.pad("scale", 6) + "  " + Report.pad("systems", 7) + "  " + "pages")
    for factor in factors {
        let abc = SourceRewriter.apply(options, to: source, scaleOverride: factor)
        let label = Report.pad(String(factor), 6)
        do {
            let svgs = try render(abc)
            let geometry = try SVGGeometry.pages(from: svgs)
            let systems = geometry.reduce(0) { $0 + $1.systems.count }
            print(label + "  " + Report.pad("\(systems)", 7, alignRight: true) + "  " + "\(svgs.count)")
        } catch {
            print(label + "  failed: \(error)")
        }
    }
    exit(0)
}

// MARK: - Report mode

let abc = SourceRewriter.apply(options, to: source)
let result = parse(abc)

let svgs: [String]
do {
    svgs = try SVGRenderer(config: renderConfig).render(result.score)
} catch {
    fail("render failed: \(error)")
}

if let directory = options.outputDirectory {
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, svg) in svgs.enumerated() {
            try svg.write(to: directory.appendingPathComponent("page\(index).svg"),
                          atomically: true, encoding: .utf8)
        }
    } catch {
        fail("cannot write to \(directory.path): \(error)")
    }
}

do {
    let report = Report(file: options.file,
                        score: result.score,
                        diagnostics: result.diagnostics,
                        pages: try SVGGeometry.pages(from: svgs))
    if options.json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    } else {
        print(report.text)
    }
} catch {
    fail("cannot read back the emitted SVG: \(error)")
}
