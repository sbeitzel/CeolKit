import CeolKitModel

struct ABCFileBuilder {
    let lines: [LogicalLine]
    let options: ParseOptions
    let preDiagnostics: [Diagnostic]

    init(lines: [LogicalLine], options: ParseOptions, preDiagnostics: [Diagnostic] = []) {
        self.lines = lines
        self.options = options
        self.preDiagnostics = preDiagnostics
    }

    func build() -> ABCFile {
        var versionLine: String? = nil
        var filePreamble: [LogicalLine] = []
        var tunes: [ABCTune] = []
        var diagnostics = preDiagnostics

        var tuneHeader: [InformationField] = []
        var tuneDirectives: [(name: String, payload: String, source: SourceRange)] = []
        var tuneMusicBody: [[MusicElement]] = []
        var tuneStartSource: SourceRange? = nil
        var missingRefNumber = false

        enum State { case preamble, header, body }
        var state = State.preamble

        func flushTune() {
            guard let start = tuneStartSource else { return }
            tunes.append(ABCTune(
                headerFields: tuneHeader,
                musicBody: tuneMusicBody,
                headerDirectives: tuneDirectives,
                source: start,
                missingReferenceNumber: missingRefNumber
            ))
            tuneHeader = []
            tuneDirectives = []
            tuneMusicBody = []
            tuneStartSource = nil
            missingRefNumber = false
        }

        func startImplicitTune(source: SourceRange) {
            // Called when a K: or music line appears without a preceding X:.
            // The preamble may contain header-like info fields; promote them.
            let promotableFields = filePreamble.compactMap { line -> InformationField? in
                guard case .informationField(let c, let p, let s) = line,
                      !"XK".contains(c) else { return nil }
                let (field, _) = parseField(code: c, payload: p, source: s)
                return field
            }
            tuneHeader = promotableFields
            tuneStartSource = source
            missingRefNumber = true
            // filePreamble entries consumed into header; keep non-field entries
            filePreamble = filePreamble.filter { line in
                if case .informationField = line { return false }
                return true
            }
            diagnostics.append(Diagnostic(
                severity: .error,
                code: .missingRequiredField,
                message: "X: field is required",
                source: source
            ))
        }

        for line in lines {
            switch state {
            case .preamble:
                switch line {
                case .versionLine(let v, _):
                    versionLine = v
                    filePreamble.append(line)
                case .informationField(let code, let payload, let source) where code == "X":
                    let (field, diags) = parseField(code: code, payload: payload, source: source)
                    diagnostics += diags
                    tuneHeader = [field]
                    tuneStartSource = source
                    state = .header
                case .informationField(let code, let payload, let source) where code == "K":
                    // Recovery: K: without X: — start implicit tune from preamble fields
                    startImplicitTune(source: source)
                    let (keyField, kDiags) = parseField(code: code, payload: payload, source: source)
                    diagnostics += kDiags
                    tuneHeader.append(keyField)
                    state = .body
                case .musicLine(let text, let source):
                    // Recovery: music line without any header — start implicit tune
                    if tuneStartSource == nil {
                        startImplicitTune(source: source)
                    }
                    let parser = MusicLineParser(text: text, lineRange: source)
                    let (elements, diags) = parser.parse()
                    diagnostics += diags
                    tuneMusicBody.append(elements)
                    state = .body
                default:
                    filePreamble.append(line)
                }

            case .header:
                switch line {
                case .empty:
                    flushTune()
                    state = .preamble
                case .informationField(let code, let payload, let source):
                    if code == "X" {
                        flushTune()
                        let (field, diags) = parseField(code: code, payload: payload, source: source)
                        diagnostics += diags
                        tuneHeader = [field]
                        tuneStartSource = source
                    } else {
                        let (field, diags) = parseField(code: code, payload: payload, source: source)
                        diagnostics += diags
                        tuneHeader.append(field)
                        if code == "K" { state = .body }
                    }
                case .directive(let name, let payload, let source):
                    tuneDirectives.append((name: name, payload: payload, source: source))
                default:
                    break
                }

            case .body:
                switch line {
                case .empty:
                    flushTune()
                    state = .preamble
                case .informationField(let code, let payload, let source) where code == "X":
                    flushTune()
                    let (field, diags) = parseField(code: code, payload: payload, source: source)
                    diagnostics += diags
                    tuneHeader = [field]
                    tuneStartSource = source
                    state = .header
                case .musicLine(let text, let source):
                    let parser = MusicLineParser(text: text, lineRange: source)
                    let (elements, diags) = parser.parse()
                    diagnostics += diags
                    tuneMusicBody.append(elements)
                case .informationField(let code, let payload, let source):
                    let (field, diags) = parseField(code: code, payload: payload, source: source)
                    diagnostics += diags
                    tuneMusicBody.append([.inlineField(field, source: source)])
                case .directive(let name, let payload, let source):
                    // Body-level directives are stored as inline field markers only.
                    // Voice-local scope is resolved in the semantic pass.
                    tuneMusicBody.append([.inlineField(
                        .unknown(code: "%" as Character, payload: "\(name) \(payload)", source: source),
                        source: source
                    )])
                default:
                    break
                }
            }
        }

        flushTune()

        return ABCFile(
            versionLine: versionLine,
            filePreamble: filePreamble,
            tunes: tunes,
            diagnostics: diagnostics
        )
    }
}
