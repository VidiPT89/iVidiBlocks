import CoreGraphics
import Foundation

/// Where every ring and sector of the well sits on screen. Rings widen
/// gently towards the rim, so outer cells do not stretch into long thin
/// arcs and inner cells stay big enough to read.
enum WellGeometry {

    /// Logical scene size. The view scales this to fit.
    static let sceneSize = CGSize(width: 400, height: 400)
    static let centre = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
    static let coreRadius: CGFloat = 52
    static let rimRadius: CGFloat = 192
    static let sectorAngle = 2 * CGFloat.pi / CGFloat(Board.sectors)

    /// Above 1 widens the outer rings at the expense of the inner ones.
    private static let flare: CGFloat = 1.15

    /// Rings counted from the core: 0 is the innermost visible ring.
    static func ringIndex(depth y: Int) -> Int {
        Board.rings - 1 - y
    }

    /// Radius of the boundary `index` rings out from the core.
    private static func boundary(_ index: Int) -> CGFloat {
        let t = CGFloat(index) / CGFloat(Board.visibleRings)
        return coreRadius + (rimRadius - coreRadius) * pow(t, flare)
    }

    static func innerRadius(depth y: Int) -> CGFloat {
        boundary(ringIndex(depth: y))
    }

    static func outerRadius(depth y: Int) -> CGFloat {
        boundary(ringIndex(depth: y) + 1)
    }

    static func midRadius(depth y: Int) -> CGFloat {
        (innerRadius(depth: y) + outerRadius(depth: y)) / 2
    }

    /// Angle of a sector's centre in well space: sector 0 straight up,
    /// sectors counting clockwise.
    static func angle(sector x: CGFloat) -> CGFloat {
        .pi / 2 - (x + 0.5) * sectorAngle
    }

    /// Well rotation that brings the given sector to the top.
    static func rotation(bringingToTop sector: Double) -> CGFloat {
        (CGFloat(sector) + 0.5) * sectorAngle
    }

    /// Centre of a cell in scene space once the well is turned by `rotation`.
    static func position(of cell: Point, rotation: CGFloat) -> CGPoint {
        let radius = midRadius(depth: cell.y)
        let theta = angle(sector: CGFloat(cell.x)) + rotation
        return CGPoint(x: centre.x + radius * cos(theta), y: centre.y + radius * sin(theta))
    }

    /// One cell's outline, pointing along +x, with a small gap all round so
    /// neighbouring cells read as separate blocks.
    static func wedgePath(depth y: Int, gap: CGFloat = 1.6) -> CGPath {
        let inner = innerRadius(depth: y) + gap / 2
        let outer = outerRadius(depth: y) - gap / 2
        let half = sectorAngle / 2
        let innerHalf = half - gap / 2 / inner
        let outerHalf = half - gap / 2 / outer
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: outer, startAngle: -outerHalf, endAngle: outerHalf, clockwise: false)
        path.addArc(center: .zero, radius: inner, startAngle: innerHalf, endAngle: -innerHalf, clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Smallest signed turn from one angle to another, so the well always
    /// takes the short way round.
    static func shortestTurn(from current: CGFloat, to target: CGFloat) -> CGFloat {
        var delta = (target - current).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }
}
