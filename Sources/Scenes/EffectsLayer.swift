import SpriteKit
import UIKit

/// Everything decorative that happens over the board: clear particles, the
/// screen flash, the shake and the danger vignette. Each effect is a no-op
/// when Reduce Motion is on, so the game stays readable without them.
final class EffectsLayer: SKNode {

    var reduceMotion = false

    private let cellSize: CGFloat
    private let boardSize: CGSize
    private let flashNode: SKSpriteNode
    private let vignetteNode: SKSpriteNode

    init(cellSize: CGFloat, boardSize: CGSize) {
        self.cellSize = cellSize
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

    /// Pulses red as the stack climbs. Driven every frame, so it only
    /// touches alpha rather than creating actions.
    func updateDanger(_ level: Double, pulse: Double) {
        guard level > 0 else {
            vignetteNode.alpha = 0
            return
        }
        let breathing = reduceMotion ? 1.0 : 0.72 + 0.28 * sin(pulse * 4)
        vignetteNode.alpha = CGFloat(level * 0.55 * breathing)
    }

    // MARK: Line clears

    /// Whitens the rows about to disappear, then bursts them into particles
    /// tinted with the colours that were sitting there.
    func lineClear(rows: [CGFloat], colors: [[UIColor]], isTetris: Bool) {
        for (index, y) in rows.enumerated() {
            let beam = SKSpriteNode(color: .white,
                                    size: CGSize(width: boardSize.width, height: cellSize))
            beam.anchorPoint = CGPoint(x: 0, y: 0.5)
            beam.position = CGPoint(x: 0, y: y)
            beam.zPosition = 15
            beam.alpha = 0
            beam.blendMode = .add
            addChild(beam)
            beam.run(.sequence([
                .fadeAlpha(to: 0.9, duration: 0.08),
                .wait(forDuration: 0.08),
                .group([.fadeOut(withDuration: 0.18),
                        .scaleY(to: 0.1, duration: 0.18)]),
                .removeFromParent()
            ]))

            guard !reduceMotion else { continue }
            let rowColors = index < colors.count ? colors[index] : []
            emitParticles(atRowY: y, colors: rowColors, count: isTetris ? 10 : 6)
        }
    }

    private func emitParticles(atRowY y: CGFloat, colors: [UIColor], count: Int) {
        guard !colors.isEmpty else { return }
        for column in 0..<Board.columns {
            let color = colors[min(column, colors.count - 1)]
            for _ in 0..<max(1, count / Board.columns + 1) {
                let shard = SKSpriteNode(color: color,
                                         size: CGSize(width: cellSize * 0.22,
                                                      height: cellSize * 0.22))
                shard.position = CGPoint(x: (CGFloat(column) + 0.5) * cellSize, y: y)
                shard.zPosition = 16
                shard.blendMode = .add
                addChild(shard)

                let dx = CGFloat.random(in: -cellSize...cellSize)
                let dy = CGFloat.random(in: cellSize * 0.4...cellSize * 2.2)
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

    // MARK: Piece feedback

    /// Vertical streak left behind by a hard drop.
    func hardDropTrail(column: Int, width: Int, fromY: CGFloat, toY: CGFloat, color: UIColor) {
        guard !reduceMotion, fromY > toY else { return }
        let trail = SKSpriteNode(color: color,
                                 size: CGSize(width: CGFloat(width) * cellSize,
                                              height: fromY - toY))
        trail.anchorPoint = CGPoint(x: 0, y: 0)
        trail.position = CGPoint(x: CGFloat(column) * cellSize, y: toY)
        trail.zPosition = 12
        trail.alpha = 0.32
        trail.blendMode = .add
        addChild(trail)
        trail.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
    }

    /// Expanding ring drawn from the centre of a successful T-spin.
    func spinRing(at point: CGPoint, color: UIColor) {
        guard !reduceMotion else { return }
        let ring = SKShapeNode(circleOfRadius: cellSize * 0.6)
        ring.position = point
        ring.strokeColor = color
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.zPosition = 17
        ring.blendMode = .add
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 4.5, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent()
        ]))
    }

    /// Golden sweep from the floor upwards for a perfect clear.
    func perfectClearSweep(color: UIColor) {
        guard !reduceMotion else { return }
        let sweep = SKSpriteNode(color: color,
                                 size: CGSize(width: boardSize.width, height: cellSize * 1.6))
        sweep.anchorPoint = CGPoint(x: 0, y: 0)
        sweep.position = CGPoint(x: 0, y: -cellSize)
        sweep.zPosition = 18
        sweep.alpha = 0.75
        sweep.blendMode = .add
        addChild(sweep)
        sweep.run(.sequence([
            .group([.moveTo(y: boardSize.height, duration: 0.55),
                    .fadeOut(withDuration: 0.55)]),
            .removeFromParent()
        ]))
    }

    /// Brief glow on the wall a rotation kicked away from.
    func wallSpark(at point: CGPoint, color: UIColor) {
        guard !reduceMotion else { return }
        let spark = SKSpriteNode(color: color,
                                 size: CGSize(width: cellSize * 0.25, height: cellSize * 2))
        spark.position = point
        spark.zPosition = 16
        spark.blendMode = .add
        spark.alpha = 0.8
        addChild(spark)
        spark.run(.sequence([
            .group([.fadeOut(withDuration: 0.22), .scaleX(to: 3, duration: 0.22)]),
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
