//
//  PageGeometry.swift
//  CeolKitSVGGeometry
//
//  The shape of one rendered page, recovered from the SVG the renderer emitted.
//

import Foundation

/// Geometry recovered from a single page of `SVGRenderer` output.
public struct PageGeometry: Sendable, Codable, Equatable {
    /// Page number as reported by the `ceolkit-meta` comment, or `nil` when absent.
    public let pageNumber: Int?
    /// The root `<svg>` element's `width` attribute, in points.
    public let width: Double
    /// The root `<svg>` element's `height` attribute, in points.
    public let height: Double
    /// One entry per staff system, in the order the renderer emitted them.
    public let systems: [SystemGeometry]

    public init(pageNumber: Int?, width: Double, height: Double, systems: [SystemGeometry]) {
        self.pageNumber = pageNumber
        self.width = width
        self.height = height
        self.systems = systems
    }
}

/// Geometry of one staff system.
public struct SystemGeometry: Sendable, Codable, Equatable {
    /// The ABC source line this system came from, as reported by the `ceolkit-meta`
    /// anchors.  `nil` when the page carries no metadata, or when the anchor count
    /// disagrees with the number of staves actually drawn.
    ///
    /// - Note: this is only as trustworthy as the anchors themselves.  See CeolKit
    ///   issue #41 — most measures carry a fabricated source range, so a value of `1`
    ///   here frequently means "unknown" rather than "line 1".
    public let abcLine: Int?
    /// Y coordinate of the topmost of the five staff lines.
    public let topY: Double
    /// Distance between adjacent staff lines — the effective `staffSize` for this system.
    public let staffLineGap: Double
    /// X coordinate where the staff lines begin.
    public let left: Double
    /// X coordinate where the staff lines end.
    public let right: Double
    /// X positions of the barlines drawn across this staff, left to right.
    ///
    /// Best-effort: recovered by looking for vertical strokes that span the staff exactly.
    /// Compound barlines (repeats, final bars) are drawn as two or three parallel strokes
    /// and are clustered back into one entry, but the result is inferred from drawing
    /// geometry rather than read from the model, so treat it as approximate.
    public let barlineXs: [Double]

    /// Horizontal extent of the staff lines.
    public var width: Double { right - left }
    /// Y coordinate of the bottommost of the five staff lines.
    public var bottomY: Double { topY + 4 * staffLineGap }

    public init(
        abcLine: Int?,
        topY: Double,
        staffLineGap: Double,
        left: Double,
        right: Double,
        barlineXs: [Double]
    ) {
        self.abcLine = abcLine
        self.topY = topY
        self.staffLineGap = staffLineGap
        self.left = left
        self.right = right
        self.barlineXs = barlineXs
    }
}

/// Raised when a page cannot be interpreted at all.
public enum SVGGeometryError: Error, CustomStringConvertible, Equatable {
    case missingRootElement
    case missingPageDimensions

    public var description: String {
        switch self {
        case .missingRootElement:    "no <svg> root element found"
        case .missingPageDimensions: "<svg> root element has no width/height attributes"
        }
    }
}
