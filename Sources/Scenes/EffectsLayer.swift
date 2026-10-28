import SpriteKit
import UIKit

/// Everything decorative that happens over the well: clear particles, the
/// screen flash, the pulse wave and the danger vignette. Each effect is a no-op
/// when Reduce Motion is on, so the game stays readable without them.
final class EffectsLayer: SKNode {

    var reduceMotion = false

    private let boardSize: CGSize
    private let flashNode: SKSpriteNode
    private let vignetteNode: SKSpriteNode

    init(boardSize: CGSize) {
        self.boardSize = boardSize
        flashNode = SKSpriteNode(color: .white, size: boardSize)
        vignetteNode = SKSpriteNode(texture: EffectsLayer.vignetteTexture(size: boardSize),
                                    size: boardSize)
        super.init()

        for node in [flashNode, vignetteNode] {
            node.anchorPoint = .zero
            node.position = .zero
            node.alpha = 0
            node.blendMode = .alpha
            addChild(node)
        }
        flashNode.zPosition = 20
        vignetteNode.zPosition = 19
        vignetteNode.blendMode = .add
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Flash

    func flash(color: UIColor, intensity: CGFloat, duration: TimeInterval = 0.18) {
        guard !reduceMotion else { return }
        flashNode.removeAllActions()
        flashNode.color = color
        flashNode.alpha = intensity
        flashNode.run(.fadeOut(withDuration: duration))
    }

    // MARK: Danger vignette

    /// Pulses red as the stack climbs towards the rim. Driven every frame, so it only
    /// touches alpha rather than creating actions.
    func updateDanger(_ level: Double, pulse: Double) {
        guard level > 0 else {
            vignetteNode.alpha = 0
            return
        }
        let breathing = reduceMotion ? 1.0 : 0.72 + 0.28 * sin(pulse * 4)
        vignetteNode.alpha = CGFloat(level * 0.55 * breathing)
    }

    // MARK: Clears

    /// Bursts the cleared cells into shards tinted with their own colours,
    /// flung outwards from the core.
    func burst(at points: [CGPoint], colors: [UIColor], centre: CGPoint, big: Bool) {
        guard !reduceMotion else { return }
        let perCell = big ? 3 : 2
        for (index, point) in points.enumerated() {
            let color = index < colors.count ? colors[index] : .white
            let away = CGVector(dx: point.x - centre.x, dy: point.y - centre.y)
            let length = max(hypot(away.dx, away.dy), 1)
            for _ in 0..<perCell {
                let shard = SKSpriteNode(color: color, size: CGSize(width: 5, height: 5))
                shard.position = point
                shard.zPosition = 16
                shard.blendMode = .add
                addChild(shard)

                let push = CGFloat.random(in: 18...46)
                let dx = away.dx / length * push + .random(in: -10...10)
                let dy = away.dy / length * push + .random(in: -10...10)
                shard.run(.sequence([
                    .group([
                        .moveBy(x: dx, y: dy, duration: 0.42),
                        .fadeOut(withDuration: 0.42),
                        .scale(to: 0.2, duration: 0.42),
                        .rotate(byAngle: .random(in: -3...3), duration: 0.42)
                    ]),
                    .removeFromParent()
                ]))
            }
        }
    }

    /// A bright band that flares along a ring as it closes.
    func ringFlare(radius: CGFloat, width: CGFloat, centre: CGPoint, color: UIColor) {
        guard !reduceMotion else { return }
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = centre
        ring.strokeColor = color
        ring.lineWidth = width
        ring.fillColor = .clear
        ring.zPosition = 15
        ring.alpha = 0
        ring.blendMode = .add
        addChild(ring)
        ring.run(.sequence([
            .fadeAlpha(to: 0.9, duration: 0.08),
            .wait(forDuration: 0.08),
            .group([.fadeOut(withDuration: 0.2), .scale(to: 1.08, duration: 0.2)]),
            .removeFromParent()
        ]))
    }

    // MARK: Piece feedback

    /// Streak left behind by a drop, from the rim down to where it landed.
    func dropTrail(centreX: CGFloat, width: CGFloat, fromY: CGFloat, toY: CGFloat, color: UIColor) {
        guard !reduceMotion, fromY > toY else { return }
        let trail = SKSpriteNode(color: color, size: CGSize(width: width, height: fromY - toY))
        trail.anchorPoint = CGPoint(x: 0.5, y: 0)
        trail.position = CGPoint(x: centreX, y: toY)
        trail.zPosition = 12
        trail.alpha = 0.32
        trail.blendMode = .add
        addChild(trail)
        trail.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
    }

    /// Expanding ring from the core for each link of a chain.
    func chainRing(at point: CGPoint, radius: CGFloat, color: UIColor) {
        guard !reduceMotion else { return }
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = point
        ring.strokeColor = color
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.zPosition = 17
        ring.blendMode = .add
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 3.8, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent()
        ]))
    }

    /// The shock wave of a core pulse, filling the well from the centre.
    func pulseWave(at point: CGPoint, radius: CGFloat, color: UIColor) {
        guard !reduceMotion else { return }
        let wave = SKShapeNode(circleOfRadius: radius)
        wave.position = point
        wave.fillColor = color.withAlphaComponent(0.35)
        wave.strokeColor = color
        wave.lineWidth = 6
        wave.zPosition = 18
        wave.blendMode = .add
        addChild(wave)
        wave.run(.sequence([
            .group([.scale(to: 4.2, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))
    }

    private static func vignetteTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.clear.cgColor,
                          UIColor.systemRed.withAlphaComponent(0.9).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0.45, 1]) else { return }
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: max(size.width, size.height) * 0.75,
                options: []
            )
        }
        return SKTexture(image: image)
    }
}
