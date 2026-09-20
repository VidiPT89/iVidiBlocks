import SpriteKit
import UIKit

private extension UIColor {
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
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

/// The surface the playfield sits on: a quiet warm gradient that briefly
/// heats up on a level change. Deliberately plain, because anything moving
/// inside the well competes with the pieces the player is reading.
final class BackgroundLayer: SKNode {

    private let boardSize: CGSize
    private let gradient: SKSpriteNode
    private var warmth: CGFloat = 0

    init(boardSize: CGSize, traits: UITraitCollection) {
        self.boardSize = boardSize
        gradient = SKSpriteNode(texture: nil, size: boardSize)
        gradient.anchorPoint = .zero
        super.init()

        gradient.zPosition = -10
        addChild(gradient)
        applyTraits(traits)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func applyTraits(_ traits: UITraitCollection) {
        gradient.texture = BackgroundLayer.gradientTexture(size: boardSize, traits: traits)
    }

    /// Nudged on a level change so the well visibly warms as the speed climbs.
    func pulseWarmth() {
        warmth = 1
    }

    func update(deltaTime: TimeInterval) {
        guard warmth > 0 else { return }
        warmth = max(0, warmth - CGFloat(deltaTime) * 0.7)
        gradient.color = .systemOrange
        gradient.colorBlendFactor = warmth * 0.22
        if warmth == 0 { gradient.colorBlendFactor = 0 }
    }

    private static func gradientTexture(size: CGSize, traits: UITraitCollection) -> SKTexture {
        let dark = traits.userInterfaceStyle == .dark
        let top = UIColor(named: "BgSecondary", in: .main, compatibleWith: traits) ?? .darkGray
        let bottom = UIColor(named: "BgPrimary", in: .main, compatibleWith: traits) ?? .black
        let ember = UIColor(named: "BrandEmber", in: .main, compatibleWith: traits) ?? .orange
        // Mixed into an opaque colour instead of layered as a translucent one,
        // so the page gradient never bleeds through the floor of the well.
        let floor = bottom.blended(with: ember, amount: dark ? 0.16 : 0.09)

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [top.cgColor, bottom.cgColor, floor.cgColor] as CFArray
            // The renderer puts y = 0 at the top, so this runs the cool tone
            // down from the ceiling into the warm glow at the floor.
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.72, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }
}
