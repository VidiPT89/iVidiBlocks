import CoreGraphics

/// Fixed 10 × 20 playfield in SpriteKit coordinates (y increases upwards).
enum WellGeometry {
    static let sceneSize = CGSize(width: 200, height: 400)
    static let centre = CGPoint(x: 100, y: 200)

    static func position(of cell: Point, rotation: CGFloat = 0) -> CGPoint {
        CGPoint(x: CGFloat(cell.x) * 20 + 10,
                y: CGFloat(Board.rings - 1 - cell.y) * 20 + 10)
    }
}
