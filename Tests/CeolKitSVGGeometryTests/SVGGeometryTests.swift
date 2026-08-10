//
//  SVGGeometryTests.swift
//  CeolKitSVGGeometryTests
//
//  Fixtures here are hand-written rather than rendered: this target deliberately does
//  not depend on the renderer, so that a geometry bug and a rendering bug cannot hide
//  each other.  End-to-end coverage lives in CeolKitSVGRendererTests.
//

import Testing
@testable import CeolKitSVGGeometry

@Suite("SVG geometry extraction")
struct SVGGeometryTests {

    /// Five evenly spaced horizontal lines sharing one x range — what `emitStaffLines`
    /// writes to open a system.
    private static func staff(topY: Double, gap: Double = 6, left: Double = 36, right: Double = 756) -> String {
        (0 ..< 5).map { index in
            let y = topY + Double(index) * gap
            return #"<line x1="\#(left)" y1="\#(y)" x2="\#(right)" y2="\#(y)" stroke="black" stroke-width="0.78"/>"#
        }.joined(separator: "\n")
    }

    private static func barline(x: Double, topY: Double, gap: Double = 6, width: Double = 0.96) -> String {
        #"<line x1="\#(x)" y1="\#(topY)" x2="\#(x)" y2="\#(topY + 4 * gap)" stroke="black" stroke-width="\#(width)"/>"#
    }

    private static func page(_ body: String, meta: String? = nil) -> String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 792 612" width="792" height="612">
        \(meta ?? "")
        \(body)
        </svg>
        """
    }

    // MARK: - Page

    @Test("Reads the page box from the root element")
    func pageBox() throws {
        let geometry = try SVGGeometry.page(from: Self.page(Self.staff(topY: 100)))
        #expect(geometry.width == 792)
        #expect(geometry.height == 612)
    }

    @Test("A page with no <svg> root is rejected")
    func missingRoot() {
        #expect(throws: SVGGeometryError.missingRootElement) {
            try SVGGeometry.page(from: "<not-svg/>")
        }
    }

    @Test("A root element without width/height is rejected")
    func missingDimensions() {
        #expect(throws: SVGGeometryError.missingPageDimensions) {
            try SVGGeometry.page(from: #"<svg viewBox="0 0 792 612"></svg>"#)
        }
    }

    // MARK: - Staff detection

    @Test("Each run of five evenly spaced shared-span lines is one system")
    func systemCount() throws {
        let svg = Self.page([Self.staff(topY: 100), Self.staff(topY: 200), Self.staff(topY: 300)]
            .joined(separator: "\n"))
        let geometry = try SVGGeometry.page(from: svg)
        #expect(geometry.systems.count == 3)
        #expect(geometry.systems.map(\.topY) == [100, 200, 300])
    }

    @Test("Staff line gap, span and derived width are reported")
    func staffMetrics() throws {
        let geometry = try SVGGeometry.page(from: Self.page(Self.staff(topY: 100, gap: 4.5, left: 36, right: 640)))
        let system = try #require(geometry.systems.first)
        #expect(system.staffLineGap == 4.5)
        #expect(system.left == 36)
        #expect(system.right == 640)
        #expect(system.width == 604)
        #expect(system.bottomY == 118)
    }

    @Test("Ledger lines are not mistaken for staff lines")
    func ledgerLinesIgnored() throws {
        // Ledger lines are notehead-width and never come five to a run.
        let ledgers = (0 ..< 6).map { index in
            #"<line x1="100" y1="\#(88 - Double(index))" x2="107" y2="\#(88 - Double(index))" stroke="black" stroke-width="0.78"/>"#
        }.joined(separator: "\n")
        let svg = Self.page(ledgers + "\n" + Self.staff(topY: 100))
        let geometry = try SVGGeometry.page(from: svg)
        #expect(geometry.systems.count == 1)
        #expect(geometry.systems.first?.topY == 100)
    }

    @Test("A run of five that is not evenly spaced is not a staff")
    func unevenRunRejected() throws {
        let uneven = [100.0, 106, 112, 118, 130].map { y in
            #"<line x1="36" y1="\#(y)" x2="756" y2="\#(y)" stroke="black" stroke-width="0.78"/>"#
        }.joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(uneven))
        #expect(geometry.systems.isEmpty)
    }

    @Test("Attributes are read by name, not by position")
    func attributeOrderIndependence() throws {
        let reordered = (0 ..< 5).map { index in
            let y = 100 + Double(index) * 6
            return #"<line stroke-width="0.78" y2="\#(y)" x2="756" stroke="black" y1="\#(y)" x1="36"/>"#
        }.joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(reordered))
        #expect(geometry.systems.count == 1)
        #expect(geometry.systems.first?.staffLineGap == 6)
    }

    // MARK: - Barlines

    @Test("Vertical strokes spanning the staff are counted as barlines")
    func barlineDetection() throws {
        let body = [
            Self.staff(topY: 100),
            Self.barline(x: 36, topY: 100),
            Self.barline(x: 400, topY: 100),
            Self.barline(x: 756, topY: 100),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.first?.barlineXs == [36, 400, 756])
    }

    @Test("The parallel strokes of a repeat mark cluster into one barline")
    func compoundBarlineClustering() throws {
        // Spacings taken from real output: a repeat mark's thick and thin strokes sit
        // about 0.8 staff spaces apart.
        let body = [
            Self.staff(topY: 100),
            Self.barline(x: 91.932, topY: 100, width: 3),
            Self.barline(x: 96.732, topY: 100),
            Self.barline(x: 400, topY: 100),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.first?.barlineXs == [91.932, 400])
    }

    @Test("A three-stroke closing repeat stays one barline")
    func threeStrokeBarlineClustering() throws {
        // `:|]` draws dots, thin and thick — chained spacings, none of them a measure wide.
        let body = [
            Self.staff(topY: 100),
            Self.barline(x: 740, topY: 100),
            Self.barline(x: 744.8, topY: 100),
            Self.barline(x: 749.6, topY: 100, width: 3),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.first?.barlineXs == [740])
    }

    @Test("Note stems are not counted as barlines")
    func stemsIgnored() throws {
        let body = [
            Self.staff(topY: 100),
            // Stems that stop short of the staff edges are excluded on height…
            #"<line x1="120" y1="84" x2="120" y2="112" stroke="black" stroke-width="0.72"/>"#,
            #"<line x1="130" y1="112" x2="130" y2="136" stroke="black" stroke-width="0.72"/>"#,
            // …and one that happens to span it exactly is excluded on stroke width,
            // being thinner than the staff lines.  Observed on real output at x=230.619.
            #"<line x1="230.619" y1="100" x2="230.619" y2="124" stroke="black" stroke-width="0.72"/>"#,
            Self.barline(x: 400, topY: 100),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.first?.barlineXs == [400])
    }

    @Test("A barline drawn twice at one x counts once")
    func duplicateBarlines() throws {
        // The emitter writes the shared barline between two measures once as the closing
        // bar of the first and once as the opening bar of the second.
        let body = [
            Self.staff(topY: 100),
            Self.barline(x: 329.075, topY: 100),
            Self.barline(x: 329.075, topY: 100),
            Self.barline(x: 756, topY: 100),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.first?.barlineXs == [329.075, 756])
    }

    @Test("Barlines are attributed to the system they cross")
    func barlinesPerSystem() throws {
        let body = [
            Self.staff(topY: 100),
            Self.barline(x: 400, topY: 100),
            Self.staff(topY: 200),
            Self.barline(x: 300, topY: 200),
            Self.barline(x: 500, topY: 200),
        ].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body))
        #expect(geometry.systems.map(\.barlineXs) == [[400], [300, 500]])
    }

    // MARK: - ceolkit-meta

    private static let meta = #"<!-- ceolkit-meta: {"page": 3, "anchors": [{"abcLine": 13, "y": 87}, {"abcLine": 14, "y": 187}]} -->"#

    @Test("Anchors supply the page number and per-system source lines")
    func metaAnchors() throws {
        let body = [Self.staff(topY: 100), Self.staff(topY: 200)].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body, meta: Self.meta))
        #expect(geometry.pageNumber == 3)
        #expect(geometry.systems.map(\.abcLine) == [13, 14])
    }

    @Test("Anchors are paired with staves positionally, not by y proximity")
    func anchorsPairedByOrder() throws {
        // Anchor y values sit above their staff by the ascender space, and by a varying
        // amount — pairing has to follow emission order rather than nearest-y.
        let body = [Self.staff(topY: 100), Self.staff(topY: 200)].joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body, meta: Self.meta))
        #expect(geometry.systems.first?.abcLine == 13)
        #expect(geometry.systems.first?.topY == 100)
    }

    @Test("A page with no metadata still yields geometry, with no source lines")
    func noMeta() throws {
        let geometry = try SVGGeometry.page(from: Self.page(Self.staff(topY: 100)))
        #expect(geometry.pageNumber == nil)
        #expect(geometry.systems.count == 1)
        #expect(geometry.systems.first?.abcLine == nil)
    }

    @Test("An anchor count that disagrees with the staff count drops the source lines")
    func anchorCountMismatch() throws {
        // Two anchors, three staves: rather than guess at an alignment, report none.
        let body = [Self.staff(topY: 100), Self.staff(topY: 200), Self.staff(topY: 300)]
            .joined(separator: "\n")
        let geometry = try SVGGeometry.page(from: Self.page(body, meta: Self.meta))
        #expect(geometry.systems.count == 3)
        #expect(geometry.systems.allSatisfy { $0.abcLine == nil })
    }

    @Test("A malformed metadata comment is ignored rather than fatal")
    func malformedMeta() throws {
        let svg = Self.page(Self.staff(topY: 100), meta: "<!-- ceolkit-meta: {not json} -->")
        let geometry = try SVGGeometry.page(from: svg)
        #expect(geometry.pageNumber == nil)
        #expect(geometry.systems.count == 1)
    }

    // MARK: - Multi-page

    @Test("pages(from:) maps over a whole render")
    func multiplePages() throws {
        let svgs = [Self.page(Self.staff(topY: 100)),
                    Self.page([Self.staff(topY: 100), Self.staff(topY: 200)].joined(separator: "\n"))]
        let geometry = try SVGGeometry.pages(from: svgs)
        #expect(geometry.map(\.systems.count) == [1, 2])
    }
}
