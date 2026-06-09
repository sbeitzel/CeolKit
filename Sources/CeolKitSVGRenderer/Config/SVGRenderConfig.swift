import Foundation

public struct SVGRenderConfig: Sendable {
    public var pageSize: PageSize
    public var margins: EdgeInsets
    public var staffSize: Double
    public var systemGap: Double
    public var justifyLastSystem: Bool

    public init(
        pageSize: PageSize = .letter,
        margins: EdgeInsets = EdgeInsets(top: 36, bottom: 36, left: 36, right: 36),
        staffSize: Double = 4.5,
        systemGap: Double? = nil,
        justifyLastSystem: Bool = false
    ) {
        self.pageSize = pageSize
        self.margins = margins
        self.staffSize = staffSize
        self.systemGap = systemGap ?? staffSize * 8
        self.justifyLastSystem = justifyLastSystem
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
