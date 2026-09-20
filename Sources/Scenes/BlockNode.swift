import SpriteKit
import UIKit

/// Renders each block face once into a cached texture. Drawing the bevel and
/// border up front keeps the per-frame cost to a plain sprite draw, which is
/// what lets a full board stay at 60 fps.
enum BlockTextureFactory {

    private struct Key: Hashable {
        let type: TetrominoType
        let size: Int
        let style: Style
        let glyph: Bool
    }

    enum Style: Hashable {
        case solid
        case ghost
    }

    private static var cache: [Key: SKTexture] = [:]

    static func texture(for type: TetrominoType,
                        size: CGFloat,
                        style: Style = .solid,
                        glyph: Bool = false,
                        traits: UITraitCollection) -> SKTexture {
        let key = Key(type: type, size: Int(size.rounded()), style: style, glyph: glyph)
        if let cached = cache[key] { return cached }

        let base = UIColor(named: type.colorName, in: .main, compatibleWith: traits)
            ?? .systemOrange
        let texture = SKTexture(image: render(base: base, size: size,
                                              style: style, glyph: glyph ? type.accessibilityGlyph : nil))
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// Textures bake in the resolved colour, so a light/dark switch has to
    /// throw the cache away.
    static func invalidate() {
        cache.removeAll(keepingCapacity: true)
    }

    private static func render(base: UIColor,
                               size: CGFloat,
                               style: Style,
                               glyph: String?) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false

        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                       format: format).image { ctx in
            let cg = ctx.cgContext
            let inset = size * 0.045
            let rect = CGRect(x: inset, y: inset,
                              width: size - inset * 2, height: size - inset * 2)
            let radius = size * 0.16
            let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)

            switch style {
            case .ghost:
                base.withAlphaComponent(0.08).setFill()
                path.fill()
                base.withAlphaComponent(0.55).setStroke()
                path.lineWidth = max(1.5, size * 0.07)
                path.stroke()

            case .solid:
                cg.saveGState()
                path.addClip()

                // Vertical bevel: lighter at the top, darker at the base.
                let top = base.adjusted(brightness: 1.18)
                let bottom = base.adjusted(brightness: 0.82)
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: [top.cgColor, base.cgColor, bottom.cgColor] as CFArray,
                                             locations: [0, 0.55, 1]) {
                    cg.drawLinearGradient(gradient,
                                          start: CGPoint(x: 0, y: 0),
                                          end: CGPoint(x: 0, y: size),
                                          options: [])
                }

                // Sheen along the top edge.
                UIColor.white.withAlphaComponent(0.30).setFill()
                UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY,
                                                 width: rect.width, height: rect.height * 0.18),
                             cornerRadius: radius * 0.6).fill()
                cg.restoreGState()

                UIColor.white.withAlphaComponent(0.30).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            guard let glyph else { return }
            let font = UIFont.systemFont(ofSize: size * 0.5, weight: .black)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black.withAlphaComponent(style == .ghost ? 0.25 : 0.42)
            ]
            let text = glyph as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2,
                                  y: (size - textSize.height) / 2),
                      withAttributes: attributes)
        }
    }
}

private extension UIColor {
    func adjusted(brightness factor: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: min(b * factor, 1), alpha: a)
    }
}

/// Recycled sprite for one cell. The scene keeps a pool of these so no
/// allocation ever happens inside the update loop.
final class BlockNode: SKSpriteNode {

    convenience init(cellSize: CGFloat) {
        self.init(texture: nil, color: .clear, size: CGSize(width: cellSize, height: cellSize))
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    func configure(type: TetrominoType,
                   cellSize: CGFloat,
                   style: BlockTextureFactory.Style,
                   glyph: Bool,
                   traits: UITraitCollection) {
        texture = BlockTextureFactory.texture(for: type, size: cellSize,
                                              style: style, glyph: glyph, traits: traits)
        size = CGSize(width: cellSize, height: cellSize)
        alpha = 1
        setScale(1)
        colorBlendFactor = 0
        isHidden = false
    }
}

/// Simple free list of block sprites attached to a parent node.
final class BlockPool {
    private var available: [BlockNode] = []
    private var inUse: [BlockNode] = []
    private let parent: SKNode
    private let cellSize: CGFloat

    init(parent: SKNode, cellSize: CGFloat) {
        self.parent = parent
        self.cellSize = cellSize
    }

    func obtain() -> BlockNode {
        let node: BlockNode
        if let recycled = available.popLast() {
            node = recycled
        } else {
            node = BlockNode(cellSize: cellSize)
            parent.addChild(node)
        }
        node.isHidden = false
        inUse.append(node)
        return node
    }

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
