//
//  SVGGeometry.swift
//  CeolKitSVGGeometry
//
//  Recovers layout geometry from emitted SVG.
//
//  This target deliberately does not import any other CeolKit module.  It reads what
//  the renderer *drew*, not what the layout engine believed, so it can be used to check
//  the one against the other.
//

import Foundation

public enum SVGGeometry {

    /// Recovers the geometry of one page of `SVGRenderer` output.
    public static func page(from svg: String) throws -> PageGeometry {
        let (width, height) = try SVGPrimitives.pageSize(in: svg)
        let lines = SVGPrimitives.lines(in: svg)
        let meta = CeolKitMeta.extract(from: svg)
        let staves = self.staves(in: lines)

        // The Nth anchor describes the Nth system, so positional pairing is exact.
        // A count mismatch means one of the two is wrong; rather than guess at an
        // alignment, drop the line numbers and leave the geometry standing on its own.
        let anchors = meta?.anchors
        let linesMatch = anchors.map { $0.count == staves.count } ?? false

        let systems = staves.enumerated().map { index, staff in
            SystemGeometry(
                abcLine: linesMatch ? anchors?[index].abcLine : nil,
                topY: staff.topY,
                staffLineGap: staff.gap,
                left: staff.left,
                right: staff.right,
                barlineXs: barlines(in: lines, crossing: staff)
            )
        }

        return PageGeometry(pageNumber: meta?.page, width: width, height: height, systems: systems)
    }

    /// Recovers the geometry of every page of a render.
    public static func pages(from svgs: [String]) throws -> [PageGeometry] {
        try svgs.map { try page(from: $0) }
    }

    // MARK: - Staff detection

    struct Staff {
        let topY: Double
        let gap: Double
        let left: Double
        let right: Double
        /// Stroke width of the staff lines themselves — the reference that separates
        /// barlines from note stems.  See `barlines(in:crossing:)`.
        let strokeWidth: Double?
    }

    /// The staff systems drawn on a page, in document order.
    ///
    /// `SVGEmitter.emitStaffLines` opens each system with exactly five consecutive
    /// horizontal lines sharing one x range.  That run is what identifies a staff and
    /// tells it apart from the ledger lines drawn later inside its measures — those are
    /// notehead-width and never come five to a run.  Requiring the five to be evenly
    /// spaced as well rules out a coincidental run spanning two adjacent systems.
    static func staves(in lines: [SVGLine]) -> [Staff] {
        let horizontals = lines.filter(\.isHorizontal)
        var staves: [Staff] = []
        var i = 0
        while i + 4 < horizontals.count {
            let run = Array(horizontals[i ..< i + 5])
            let sharesXRange = run.allSatisfy { $0.x1 == run[0].x1 && $0.x2 == run[0].x2 }
            let gaps = zip(run, run.dropFirst()).map { $1.y1 - $0.y1 }
            let evenlySpaced = gaps.allSatisfy { abs($0 - gaps[0]) < 0.001 } && gaps[0] > 0

            if sharesXRange && evenlySpaced {
                staves.append(Staff(topY: run[0].y1, gap: gaps[0],
                                    left: run[0].x1, right: run[0].x2,
                                    strokeWidth: run[0].strokeWidth))
                i += 5
            } else {
                i += 1
            }
        }
        return staves
    }

    // MARK: - Barline detection

    /// X positions of the barlines drawn across `staff`, left to right.
    ///
    /// Inferred from drawing geometry, in two steps.  A barline runs the full height of
    /// the staff — but so does the occasional note stem, so height alone over-counts.
    /// The second filter is stroke width: the emitter draws stems thinner than the staff
    /// lines and barlines thicker (0.12, 0.13 and 0.16 staff sizes respectively), so the
    /// staff's own stroke width is the threshold between them, and it scales with
    /// `%%ceolkit:scale` exactly as the two things being separated do.
    ///
    /// This reads drawing output rather than the model, so it stays approximate: it
    /// rests on those three constants keeping their present order.
    static func barlines(in lines: [SVGLine], crossing staff: Staff) -> [Double] {
        let tolerance = staff.gap * 0.1
        let bottomY = staff.topY + 4 * staff.gap

        let xs = lines
            .filter(\.isVertical)
            .filter { abs($0.y1 - staff.topY) < tolerance && abs($0.y2 - bottomY) < tolerance }
            .filter { line in
                // Keep the stroke when either width is unknown: better to over-report
                // than to silently drop barlines from output we don't fully recognise.
                guard let stroke = line.strokeWidth, let reference = staff.strokeWidth else { return true }
                return stroke > reference
            }
            .map(\.x1)
            .sorted()

        // Cluster the strokes of a compound barline back together.  Measured on real
        // output the strokes of a repeat mark sit about 0.8 staff spaces apart, while
        // the gap between two real barlines is at least a measure wide.  Chaining off
        // the previous stroke rather than the cluster's first one keeps a three-stroke
        // mark (`:|]`) from splitting in two.
        let clusterWidth = staff.gap
        var clusters: [Double] = []
        var previous: Double?
        for x in xs {
            if previous.map({ x - $0 >= clusterWidth }) ?? true {
                clusters.append(x)
            }
            previous = x
        }
        return clusters
    }
}
