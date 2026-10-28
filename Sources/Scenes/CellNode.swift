import SpriteKit
import UIKit

/// One cell of the well, drawn as a wedge pointing along +x and turned into
/// its sector. Cells are recycled rather than rebuilt, and each ring's
/// outline is built once, so a full well costs no path work per frame.
final class CellNode: SKShapeNode {

    enum Style {
        case solid
        case ghost
    }

    private static var paths: [Int: CGPath] = [:]

    private let glyphLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
    private var depth = -1

    override init() {
        super.init()
        glyphLabel.verticalAlignmentMode = .center
        glyphLabel.horizontalAlignmentMode = .center
        glyphLabel.fontSize = 11
        glyphLabel.zRotation = -.pi / 2
        addChild(glyphLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func path(depth y: Int) -> CGPath {
        if let cached = paths[y] { return cached }
        let path = WellGeometry.wedgePath(depth: y)
        paths[y] = path
        return path
    }

    /// Places the wedge on a cell and paints it.
    func configure(cell: Point, color: UIColor, style: Style, glyph: String?) {
        if depth != cell.y {
            depth = cell.y
            path = CellNode.path(depth: cell.y)
            glyphLabel.position = CGPoint(x: WellGeometry.midRadius(depth: cell.y), y: 0)
        }
        zRotation = WellGeometry.angle(sector: CGFloat(cell.x))
        isAntialiased = true

        switch style {
        case .solid:
            fillColor = color
            strokeColor = UIColor.white.withAlphaComponent(0.32)
            lineWidth = 1
            glowWidth = 0
        case .ghost:
            fillColor = color.withAlphaComponent(0.1)
            strokeColor = color.withAlphaComponent(0.65)
            lineWidth = 1.5
            glowWidth = 0
        }

        glyphLabel.text = glyph
        glyphLabel.isHidden = glyph == nil
        glyphLabel.fontColor = UIColor.black.withAlphaComponent(style == .ghost ? 0.25 : 0.45)
        alpha = 1
        setScale(1)
        isHidden = false
    }

    /// Washes the cell towards white while it waits to clear.
    func highlight(_ base: UIColor) {
        fillColor = base.mixed(with: .white, amount: 0.65)
    }
}

extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1)
    }
}

/// Simple free list of cell nodes attached to a parent node.
final class CellPool {
    private var available: [CellNode] = []
    private var inUse: [CellNode] = []
    private let parent: SKNode

    init(parent: SKNode) {
        self.parent = parent
    }

    func obtain() -> CellNode {
        let node: CellNode
        if let recycled = available.popLast() {
            node = recycled
        } else {
            node = CellNode()
            parent.addChild(node)
        }
        node.isHidden = false
        inUse.append(node)
        return node
    }

    var active: [CellNode] { inUse }

    /// Hides everything handed out since the last reset, ready to be reused.
    func recycleAll() {
        for node in inUse {
            node.isHidden = true
            node.removeAllActions()
        }
        available.append(contentsOf: inUse)
        inUse.removeAll(keepingCapacity: true)
    }
}
