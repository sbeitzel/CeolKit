import CeolKitModel

/// Pass 1½: brings a tune's voices into agreement about how much music each source line
/// holds, so the line breaker can pick break points that are legal for all of them.
///
/// The semantic pass gives each voice one `Staff` per source line-break, so in a well-formed
/// parallel source the voices already agree and this is a pure pass-through.  What it exists
/// for is the source that does not: voices of unequal measure counts, or a `$`/`!` break in
/// one voice that the others do not have.
///
/// On disagreement the short voice is **padded**, never dropped back to sequential layout —
/// that is the confusing rendering this whole grouping exists to remove.  The padding is an
/// invisible full-measure rest (`X`): the source did not write silence, it wrote nothing, and
/// printing rests the author never typed would misrepresent the music.  Staff and bar lines
/// still draw, because they are group furniture, so a padded measure reads as "this voice has
/// nothing here" rather than as an engraving error.
///
/// Every divergence produces a `.voiceLengthMismatch` warning naming the voices and the
/// measure index where they parted, at `.warning` severity: the render succeeds, and says
/// what it had to do to succeed.
enum VoiceAligner {

    /// One source line's music, across every voice of the tune.
    struct AlignedStave {
        /// `measures[voiceIndex]` — one entry per voice, all of the same count.
        let measures: [[Measure]]
        /// How many of each voice's measures the source actually wrote; everything from
        /// there to ``measureCount`` is padding this pass invented.
        ///
        /// Recorded rather than recognised later: an invisible full-measure rest is
        /// something an author may legitimately write, and a shared staff has to drop the
        /// padding while keeping the `X` that was typed (see ``SharedStaffMerger``).
        let realMeasureCounts: [Int]

        var measureCount: Int { measures.first?.count ?? 0 }

        /// Whether `voice` has nothing of its own in `column`.
        func isPadding(voice: Int, column: Int) -> Bool {
            guard realMeasureCounts.indices.contains(voice) else { return false }
            return column >= realMeasureCounts[voice]
        }
    }

    /// Aligns `voices` stave by stave, padding wherever they disagree.
    ///
    /// Alignment is by *stave index*, not by running measure count: staves are source lines,
    /// and parallel voices are written line for line.  A voice with fewer staves than the
    /// tune's widest therefore gains whole padded lines at the end rather than having its
    /// music silently slide up into someone else's line.
    ///
    /// Only the *tail* is ever short: a voice the source left out of a line-set part way
    /// through carries an empty `Staff` at that index (#102), so what arrives here is already
    /// in the tune's stave numbering and the padding has nothing to guess at.
    ///
    /// - Returns: One entry per stave, in source order.  Empty when `voices` is empty.
    static func align(_ voices: [Voice], into diagnostics: inout [Diagnostic]) -> [AlignedStave] {
        guard !voices.isEmpty else { return [] }
        // The single-voice case has nothing to align and nothing to warn about.
        guard voices.count > 1 else {
            return voices[0].staves.map {
                AlignedStave(measures: [$0.measures], realMeasureCounts: [$0.measures.count])
            }
        }

        let staveCount = voices.reduce(0) { max($0, $1.staves.count) }
        var result: [AlignedStave] = []
        result.reserveCapacity(staveCount)
        // Running measure index across the whole tune, so a diagnostic can name the bar the
        // reader would count to rather than a position within some line.
        var measureOrigin = 0
        // The unit note length each voice's filler is written in, carried across staves so a
        // voice that skips a line entirely still pads in the unit it was last in.
        var fillUnits = voices.map { voice in
            voice.staves.lazy.flatMap(\.measures).first?.unitNoteLength
                ?? voice.unitNoteLength
                ?? Fraction(numerator: 1, denominator: 8)
        }

        for staveIndex in 0..<staveCount {
            let perVoice = voices.map { $0.staves.indices.contains(staveIndex) ? $0.staves[staveIndex].measures : [] }
            let width = perVoice.reduce(0) { max($0, $1.count) }

            if let diagnostic = mismatch(perVoice, voices: voices, width: width,
                                         measureOrigin: measureOrigin) {
                diagnostics.append(diagnostic)
            }

            // Padding is written in whatever unit note length the voice is in here: the last
            // real measure's, or — for a stave the voice supplied nothing for — the one it
            // was in when it last had something to say (issue #122).
            let padded = perVoice.indices.map { voice -> [Measure] in
                let unit = perVoice[voice].last?.unitNoteLength ?? fillUnits[voice]
                fillUnits[voice] = unit
                return pad(perVoice[voice], to: width, unitNoteLength: unit)
            }
            result.append(AlignedStave(measures: padded,
                                       realMeasureCounts: perVoice.map(\.count)))
            measureOrigin += width
        }

        return result
    }

    // MARK: - Private

    /// The warning for one stave whose voices did not all supply the same number of measures,
    /// or `nil` when they did.
    private static func mismatch(_ perVoice: [[Measure]], voices: [Voice], width: Int,
                                 measureOrigin: Int) -> Diagnostic? {
        let short = perVoice.indices.filter { perVoice[$0].count < width }
        guard !short.isEmpty,
              let longest = perVoice.indices.max(by: { perVoice[$0].count < perVoice[$1].count })
        else { return nil }

        let names = short.map { "\(label(voices[$0].id)) has \(perVoice[$0].count)" }
            .joined(separator: ", ")
        // The first measure some voice does not have — the earliest bar where they part.
        let divergesAt = measureOrigin + short.map { perVoice[$0].count }.min()! + 1

        return Diagnostic(
            severity: .warning,
            code: .voiceLengthMismatch,
            message: "voices disagree on the length of this line: \(label(voices[longest].id)) "
                + "has \(width) measures, \(names). Padding the short "
                + "\(short.count == 1 ? "voice" : "voices") with invisible rests so the staves stay aligned.",
            source: perVoice[longest].first?.source
                ?? voices[longest].source,
            related: short.compactMap { perVoice[$0].last?.source },
            hint: "measure \(divergesAt) is where they part; give every voice the same number "
                + "of measures per line so the bar lines align."
        )
    }

    /// How a voice is named in a diagnostic.
    private static func label(_ id: VoiceId) -> String {
        switch id {
        case .named(let name): "V:\(name)"
        case .all:             "V:*"
        }
    }

    /// Extends `measures` to `width` with invisible full-measure rests.
    ///
    /// The padding borrows the source range of the measure it follows so the padded bars
    /// still point somewhere real in the file; where there is nothing to follow — a voice
    /// that supplied no measures for this line at all — it falls back to the empty range.
    private static func pad(_ measures: [Measure], to width: Int,
                            unitNoteLength: Fraction) -> [Measure] {
        guard measures.count < width else { return measures }
        let source = measures.last?.source ?? .emptySourceRange
        let bar = BarLine(kind: .single, source: source)
        let rest = Rest(kind: .fullMeasureInvisible,
                        duration: Fraction(numerator: 1, denominator: 1),
                        decorations: [], source: source)
        let filler = Measure(openingBar: bar, events: [.rest(rest)], closingBar: bar,
                             endingNumber: nil, source: source,
                             unitNoteLength: unitNoteLength)
        return measures + Array(repeating: filler, count: width - measures.count)
    }
}
