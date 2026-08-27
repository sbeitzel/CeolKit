import Testing
import CeolKitModel
import CeolKitParser
import CeolKitSVGGeometry
@testable import CeolKitSVGRenderer

/// Issue #57: a `V:` `name=` is printed left of the tune's first system and `sname=` left of
/// every later one, and the space they stand in is reserved before the music is broken into
/// lines (ABC v2.2 §4.1).
///
/// End to end — source in, SVG out — for the same reason ``StaffBracketTests`` is: the label
/// and the gutter only mean anything together.  The reservation is right when the label lands
/// inside the page margin and the music still reaches the right one.
@Suite("Voice Labels")
struct VoiceLabelTests {

    private let config = SVGRenderConfig()

    /// One run of text in the emitted drawing.
    private struct Label {
        let text: String, x: Double, y: Double, fontSize: Double, anchor: String
    }

    private func render(_ abc: String, config: SVGRenderConfig? = nil)
    -> (svg: String, staves: [SystemGeometry]) {
        // `.both` so the strings stay in the document as `<text>` alongside the outlines the
        // renderer actually paints: the geometry asserted here is the outlines', which are
        // laid out from the same origin and anchor.
        var effective = config ?? self.config
        effective.textRendering = .both
        let score = CeolKitParser().parse(abc, options: .default).score
        var diagnostics: [Diagnostic] = []
        let svgs = try! SVGRenderer(config: effective).render(score, diagnostics: &diagnostics)
        return (svgs.joined(), try! SVGGeometry.pages(from: svgs).flatMap(\.systems))
    }

    private func texts(in svg: String) -> [Label] {
        svg.matches(of: /<text x="([-0-9.]+)" y="([-0-9.]+)" font-family="[^"]*" font-size="([-0-9.]+)"([^>]*)>([^<]*)<\/text>/)
            .compactMap { match in
                guard let x = Double(match.1), let y = Double(match.2),
                      let size = Double(match.3) else { return nil }
                let anchor = String(match.4).firstMatch(of: /text-anchor="([a-z]+)"/)
                    .map { String($0.1) } ?? "start"
                return Label(text: String(match.5), x: x, y: y, fontSize: size, anchor: anchor)
            }
    }

    /// The label standing in `staff`'s own gutter, or `nil` where it has none.
    ///
    /// Matched against the staff it names rather than against a page-wide left edge: a tune
    /// whose voices have names but no subnames indents its first system and nothing else,
    /// so the first system's labels sit to the *right* of where later staves begin.
    private func gutterLabel(_ svg: String, staff: SystemGeometry) -> Label? {
        texts(in: svg).first { $0.anchor == "end" && $0.x < staff.left
                               && $0.y > staff.topY && $0.y < staff.bottomY }
    }

    /// The gutter labels of `staves`, in staff order, skipping the staves that have none.
    private func gutterLabels(_ svg: String, staves: [SystemGeometry]) -> [Label] {
        staves.compactMap { gutterLabel(svg, staff: $0) }
    }

    /// Two voices with the given `V:` attributes, two source lines of two bars each — so the
    /// tune has a first system and a later one.
    private func twoVoices(_ first: String, _ second: String, directive: String = "") -> String {
        ([
            "X:1", "T:Two Voices", "M:4/4", "L:1/8", directive, "K:D",
            "V:1 \(first)", "V:2 \(second)",
            "[V:1] abcd efga | bage dcBA |",
            "[V:2] ABcd efga | bage dcBA |",
            "[V:1] abcd efga | bage dcBA |",
            "[V:2] ABcd efga | bage dcBA |",
        ] as [String]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private let named = #"name="Soprano" sname="S""#
    private let alto  = #"name="Alto" sname="A""#

    // MARK: - What gets printed

    @Test("name= labels the first system and sname= every later one")
    func namesThenSubnames() {
        let (svg, staves) = render(twoVoices(named, alto))
        #expect(staves.count == 4)
        let labels = gutterLabels(svg, staves: staves)
        #expect(labels.map(\.text) == ["Soprano", "Alto", "S", "A"])
    }

    @Test("A voice with a name but no sname is labelled once and then not again")
    func subnameDoesNotFallBackToTheName() {
        let (svg, staves) = render(twoVoices(#"name="Soprano""#, #"name="Alto""#))
        #expect(gutterLabels(svg, staves: staves).map(\.text) == ["Soprano", "Alto"])
    }

    @Test("A voice with sname= but no name= is unlabelled until its second system")
    func subnameAloneLabelsOnlyLaterSystems() {
        let (svg, staves) = render(twoVoices(#"sname="S""#, #"sname="A""#))
        #expect(gutterLabels(svg, staves: staves).map(\.text) == ["S", "A"])
    }

    @Test("A tune that names no voice draws no gutter text at all")
    func unnamedVoicesDrawNothing() {
        let (svg, staves) = render(twoVoices("", ""))
        #expect(gutterLabels(svg, staves: staves).isEmpty)
    }

    // MARK: - Placement

    @Test("The labels of one system right-align on a common edge")
    func labelsShareTheirRightEdge() {
        let (svg, staves) = render(twoVoices(named, alto))
        let labels = gutterLabels(svg, staves: staves)
        #expect(labels[0].x == labels[1].x)
        #expect(labels[2].x == labels[3].x)
        // The subnames are shorter, so their system indents less and their edge sits left of
        // the first system's — the labels are what the gutter is measured from.
        #expect(labels[2].x < labels[0].x)
    }

    @Test("Each label is centred on the staff it names")
    func labelsAreCentredOnTheirStaff() {
        let (svg, staves) = render(twoVoices(named, alto))
        let labels = gutterLabels(svg, staves: staves)
        for (label, staff) in zip(labels, staves) {
            let expected = staff.topY
                + VoiceLabelGutter.baselineOffset(staffSize: staff.staffLineGap)
            #expect(abs(label.y - expected) < 1e-6)
            // Inside the staff, which is the point of centring it there.
            #expect(label.y > staff.topY && label.y < staff.bottomY)
        }
    }

    @Test("The label is set at the voice-label size, which scales with the music")
    func labelFontSizeScalesWithTheStaff() {
        let (svg, staves) = render(twoVoices(named, alto))
        let label = gutterLabels(svg, staves: staves)[0]
        #expect(abs(label.fontSize
                    - VoiceLabelGutter.fontSize(staffSize: staves[0].staffLineGap)) < 1e-6)
    }

    // MARK: - Reservation

    @Test("A labelled system starts right of the margin, and an unlabelled one does not")
    func labelsIndentTheStaves() {
        let plain = render(twoVoices("", "")).staves
        let labelled = render(twoVoices(named, alto)).staves

        #expect(plain.allSatisfy { $0.left == config.margins.left })
        #expect(labelled.allSatisfy { $0.left > config.margins.left })
        // Both staves of a system start at the same x: the gutter belongs to the system, not
        // to the staff with the longest name.
        #expect(labelled[0].left == labelled[1].left)
        #expect(labelled[2].left == labelled[3].left)
        // …and the later system, carrying only subnames, indents less than the first.
        #expect(labelled[2].left < labelled[0].left)
    }

    @Test("No label crosses the left margin")
    func nothingCrossesTheLeftMargin() {
        let (svg, staves) = render(twoVoices(named, alto))
        // Right-aligned runs, so subtract the width the emitter laid them out at.
        let font = OutlineFontSet.textFace()
        for label in gutterLabels(svg, staves: staves) {
            let width = font?.width(of: label.text, fontSize: label.fontSize) ?? 0
            #expect(label.x - width >= config.margins.left - 1e-6)
        }
    }

    @Test("The music still ends on the right margin: the gutter came out of the line")
    func gutterIsTakenOutOfTheLine() {
        var config = config
        config.justifyLastSystem = true
        let rightMargin = config.pageSize.width - config.margins.right
        for abc in [twoVoices("", ""), twoVoices(named, alto)] {
            let staves = render(abc, config: config).staves
            #expect(staves.allSatisfy { abs($0.right - rightMargin) < 0.5 })
        }
    }

    @Test("The gutter scales with the music")
    func gutterScalesWithTheTune() {
        let full = render(twoVoices(named, alto)).staves
        let half = render(twoVoices(named, alto, directive: "%%ceolkit:scale 0.5")).staves
        let fullIndent = full[0].left - config.margins.left
        let halfIndent = half[0].left - config.margins.left
        #expect(abs(halfIndent - fullIndent / 2) < 1e-6)
    }

    // MARK: - Alongside the brackets

    @Test("The labels stand outside the bracket, which stands outside the staves")
    func labelsStandLeftOfTheBracket() throws {
        let (svg, staves) = render(twoVoices(named, alto, directive: "%%score [1 2]"))
        let label = try #require(gutterLabels(svg, staves: staves).first)

        // The bracket spine over the first system: the one vertical stroke left of its
        // staves that starts on its top staff line.  Anchored to that system because the
        // later one, carrying only subnames, indents less and so stands further left.
        let spineX = svg.matches(of: /<line x1="([-0-9.]+)" y1="([-0-9.]+)" x2="([-0-9.]+)"/)
            .compactMap { match -> Double? in
                guard let x1 = Double(match.1), let y1 = Double(match.2),
                      let x2 = Double(match.3),
                      abs(x1 - x2) < 1e-9, x1 < staves[0].left,
                      abs(y1 - staves[0].topY) < 1e-3 else { return nil }
                return x1
            }.min()
        let spine = try #require(spineX)
        #expect(label.x < spine)
        #expect(spine < staves[0].left)
    }

    @Test("Adding a bracket to a labelled tune indents it further, not the same")
    func bracketAndGutterAreBothReserved() {
        let labelled = render(twoVoices(named, alto)).staves
        let both = render(twoVoices(named, alto, directive: "%%score [1 2]")).staves
        #expect(both[0].left > labelled[0].left)
    }

    // MARK: - Outline rendering

    @Test("The label reaches the page as geometry, not as a bare <text>")
    func labelIsDrawnAsOutlines() throws {
        // The renderer's own default, which is what every non-browser rasteriser needs.
        let score = CeolKitParser().parse(twoVoices(named, alto), options: .default).score
        var diagnostics: [Diagnostic] = []
        let svg = try SVGRenderer(config: config).render(score, diagnostics: &diagnostics).joined()
        let staves = try SVGGeometry.pages(from: [svg]).flatMap(\.systems)

        #expect(!svg.contains("<text"))
        let inGutter = svg.matches(of: /<use [^>]*transform="translate\(([-0-9.]+)\s/)
            .compactMap { Double($0.1) }
            .filter { $0 < staves[0].left }
        #expect(!inGutter.isEmpty)
    }
}
