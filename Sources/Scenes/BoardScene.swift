import SpriteKit
import UIKit

/// Draws the fixed rectangular playfield and routes touch input to the engine.
final class BoardScene: SKScene {

    static let boardSize = WellGeometry.sceneSize

    let engine: GameEngine
    var onEvent: ((GameEvent) -> Void)?
    /// Fired after every tick so the HUD can pull fresh numbers.
    var onFrame: (() -> Void)?
    var colorBlindMode = false { didSet { lockedDirty = true } }
    var reduceMotion = false

    private let worldNode = SKNode()
    /// Everything that turns with the well: grid, locked cells, ghost, shard.
    private let wellNode = SKNode()
    private let gridNode = SKShapeNode()
    private let lockedLayer = SKNode()
    private let ghostLayer = SKNode()
    private let pieceLayer = SKNode()

    private var lockedPool: CellPool!
    private var ghostPool: CellPool!
    private var piecePool: CellPool!

    private var lastUpdate: TimeInterval = 0
    private var lockedDirty = true
    private var traits: UITraitCollection
    /// The well's on-screen turn, eased towards the engine's aim.

    // Gesture bookkeeping
    private var touchStart: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var lastDragStep = 0
    private var didDrag = false
    private var isSoftDropping = false

    private let dragStep: CGFloat = 26
    private let deadZone: CGFloat = 9
    private let dropVelocity: CGFloat = 820

    init(engine: GameEngine, traits: UITraitCollection) {
        self.engine = engine
        self.traits = traits
        super.init(size: Self.boardSize)

        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }
        addChild(worldNode)

        wellNode.position = .zero
        gridNode.zPosition = -5
        ghostLayer.zPosition = 0
        lockedLayer.zPosition = 1
        pieceLayer.zPosition = 2

        for node in [gridNode, ghostLayer, lockedLayer, pieceLayer] as [SKNode] {
            wellNode.addChild(node)
        }
        for node in [wellNode] as [SKNode] {
            worldNode.addChild(node)
        }

        lockedPool = CellPool(parent: lockedLayer)
        ghostPool = CellPool(parent: ghostLayer)
        piecePool = CellPool(parent: pieceLayer)

        applyTraits(traits)
    }

    // MARK: Theme

    func applyTraits(_ traits: UITraitCollection) {
        self.traits = traits
        gridNode.path = BoardScene.gridPath()
        gridNode.strokeColor = uiColor("GridLine")
        gridNode.lineWidth = 1
        lockedDirty = true

        // Recolour rather than rebuild, so a theme switch never interrupts play.
        worldNode.alpha = 0.85
        worldNode.run(.fadeAlpha(to: 1, duration: 0.25))
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let elapsed: TimeInterval
        let delta: TimeInterval
        if lastUpdate == 0 {
            elapsed = 1.0 / 60.0
            delta = elapsed
        } else {
            // Clamp so a stall (backgrounding, a long frame) never teleports
            // the shard into the core.
            elapsed = max(0, currentTime - lastUpdate)
            delta = min(elapsed, 1.0 / 20.0)
        }
        lastUpdate = currentTime

        engine.update(deltaTime: delta, clockDeltaTime: elapsed)

        for event in engine.drainEvents() {
            handle(event)
            onEvent?(event)
        }


        renderActivePiece()
        if lockedDirty {
            renderLockedCells()
            lockedDirty = false
        }

        onFrame?()
    }

    // MARK: Rendering

    private func renderLockedCells() {
        lockedPool.recycleAll()
        let clearing = Set(engine.pendingClear)

        for y in Board.bufferRings..<Board.rings {
            for x in 0..<Board.sectors {
                guard let color = engine.board[x, y] else { continue }
                let cell = Point(x: x, y: y)
                let base = uiColor(color.colorName)
                let node = lockedPool.obtain()
                node.configure(cell: cell, color: base, style: .solid, glyph: glyph(color))
                if clearing.contains(cell) { node.highlight(base) }
            }
        }
    }

    private func renderActivePiece() {
        piecePool.recycleAll()
        ghostPool.recycleAll()

        if let ghost = engine.ghost {
            for cell in ghost.cells where cell.y >= Board.bufferRings {
                ghostPool.obtain().configure(cell: cell, color: uiColor(ghost.color.colorName),
                                             style: .ghost, glyph: nil)
            }
        }

        guard let piece = engine.current else { return }
        for cell in piece.cells where cell.y >= Board.bufferRings {
            piecePool.obtain().configure(cell: cell, color: uiColor(piece.color.colorName),
                                         style: .solid, glyph: glyph(piece.color))
        }
    }

    private func glyph(_ color: ShardColor) -> String? {
        colorBlindMode ? color.accessibilityGlyph : nil
    }

    // MARK: Reacting to engine events

    private func handle(_ event: GameEvent) {
        switch event {
        case .locked, .cleared, .spawned, .gameOver: lockedDirty = true
        default: break
        }
    }

    private func uiColor(_ name: String) -> UIColor {
        UIColor(named: name, in: .main, compatibleWith: traits) ?? .systemOrange
    }

    // MARK: Touch input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touchStart = touch.location(in: self)
        touchStartTime = touch.timestamp
        lastDragStep = 0
        didDrag = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let dx = point.x - touchStart.x
        let dy = point.y - touchStart.y

        if abs(dx) > abs(dy) {
            let steps = Int((dx / dragStep).rounded(.towardZero))
            if steps != lastDragStep {
                let delta = steps - lastDragStep
                for _ in 0..<abs(delta) { engine.move(dx: delta > 0 ? 1 : -1) }
                lastDragStep = steps
                didDrag = true
            }
            if isSoftDropping {
                isSoftDropping = false
                engine.setSoftDrop(false)
            }
        } else if dy < -deadZone {
            if !isSoftDropping {
                isSoftDropping = true
                engine.setSoftDrop(true)
            }
            didDrag = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let dx = point.x - touchStart.x
        let dy = point.y - touchStart.y
        let elapsed = max(touch.timestamp - touchStartTime, 0.001)

        if isSoftDropping {
            isSoftDropping = false
            engine.setSoftDrop(false)
        }

        let verticalSpeed = CGFloat(abs(dy)) / CGFloat(elapsed)
        if dy < -deadZone, verticalSpeed > dropVelocity, abs(dy) > abs(dx) {
            engine.hardDrop()
            return
        }
        guard !didDrag, abs(dx) < deadZone, abs(dy) < deadZone else { return }
        engine.rotate(clockwise: point.x > WellGeometry.centre.x)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSoftDropping {
            isSoftDropping = false
            engine.setSoftDrop(false)
        }
    }

    // MARK: Grid

    /// Ring circles and sector spokes, in well space.
    private static func gridPath() -> CGPath {
        let path = CGMutablePath()
        for x in 0...Board.sectors {
            path.move(to: CGPoint(x: x * 20, y: 0))
            path.addLine(to: CGPoint(x: x * 20, y: 400))
        }
        for y in 0...Board.visibleRings {
            path.move(to: CGPoint(x: 0, y: y * 20))
            path.addLine(to: CGPoint(x: 200, y: y * 20))
        }
        return path
    }
}
