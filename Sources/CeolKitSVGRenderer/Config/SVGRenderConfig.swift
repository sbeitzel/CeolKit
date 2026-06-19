import Foundation

public struct SVGRenderConfig: Sendable {
    public var pageSize: PageSize
    public var margins: EdgeInsets
    public var staffSize: Double
    /// Vertical gap added between systems within a single tune.
    public var systemGap: Double
    /// Vertical gap added after the last system of a tune, before the next tune's title block.
    public var tuneGap: Double
    public var justifyLastSystem: Bool
    public var straightFlags: Bool
    public var graceSlurs: Bool

    public init(
        pageSize: PageSize = .letter,
        margins: EdgeInsets = EdgeInsets(top: 36, bottom: 36, left: 36, right: 36),
        staffSize: Double = 6.0,
        systemGap: Double? = nil,
        tuneGap: Double? = nil,
        justifyLastSystem: Bool = false,
        straightFlags: Bool = false,
        graceSlurs: Bool = true
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.staffSize = staffSize
        self.systemGap = systemGap ?? staffSize * 4
        self.tuneGap = tuneGap ?? staffSize * 16
        self.justifyLastSystem = justifyLastSystem
        self.straightFlags = straightFlags
        self.graceSlurs = graceSlurs
    }
}

public struct PageSize: Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let a4     = PageSize(width: 595.28, height: 841.89)
    public static let letter = PageSize(width: 612,    height: 792)
    public static let a3     = PageSize(width: 841.89, height: 1190.55)

    public var landscape: PageSize { PageSize(width: height, height: width) }
}

public struct EdgeInsets: Sendable {
    public var top, bottom, left, right: Double

    public init(top: Double, bottom: Double, left: Double, right: Double) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}
