import SpriteKit
import UIKit

/// Renders the well and turns raw touches into engine input. The scene owns
/// the frame clock: it ticks the engine, then draws whatever the engine says
/// is true. It never decides any rule itself.
///
/// The falling shard is always drawn at the top. Moving it sideways turns
/// the whole well underneath it instead, so the player never has to read a
/// shard upside down at the bottom of the circle.
final class BoardScene: SKScene {

    static let boardSize = WellGeometry.sceneSize

    let engine: GameEngine
    var onEvent: ((GameEvent) -> Void)?
    /// Fired after every tick so the HUD can pull fresh numbers.
    var onFrame: (() -> Void)?
    var colorBlindMode = false { didSet { lockedDirty = true } }
    var reduceMotion = false {
        didSet { effects.reduceMotion = reduceMotion }
    }

    private let worldNode = SKNode()
    /// Everything that turns with the well: grid, locked cells, ghost, shard.
    private let wellNode = SKNode()
    private let gridNode = SKShapeNode()
    private let lockedLayer = SKNode()
    private let ghostLayer = SKNode()
    private let pieceLayer = SKNode()
    private let coreNode = SKShapeNode(circleOfRadius: WellGeometry.coreRadius - 3)
    private let chargeNode = SKShapeNode()
    private let effects: EffectsLayer
    private let background: BackgroundLayer

    private var lockedPool: CellPool!
    private var ghostPool: CellPool!
    private var piecePool: CellPool!

    private var lastUpdate: TimeInterval = 0
    private var lockedDirty = true
    private var traits: UITraitCollection
    /// The well's on-screen turn, eased towards the engine's aim.
    private var rotation: CGFloat = 0
    private var shownCharge = -1.0

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
        self.effects = EffectsLayer(boardSize: Self.boardSize)
        self.background = BackgroundLayer(boardSize: Self.boardSize, traits: traits)
        super.init(size: Self.boardSize)

        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .clear
        rotation = WellGeometry.rotation(bringingToTop: Double(engine.aim))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }
        addChild(worldNode)

        wellNode.position = WellGeometry.centre
        gridNode.zPosition = -5
        ghostLayer.zPosition = 0
        lockedLayer.zPosition = 1
        pieceLayer.zPosition = 2
        coreNode.position = WellGeometry.centre
        coreNode.zPosition = 3
        chargeNode.position = WellGeometry.centre
        chargeNode.zPosition = 4
        chargeNode.lineCap = .round
        effects.zPosition = 10

        for node in [gridNode, ghostLayer, lockedLayer, pieceLayer] as [SKNode] {
            wellNode.addChild(node)
        }
        for node in [background, wellNode, coreNode, chargeNode, effects] as [SKNode] {
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
        coreNode.fillColor = uiColor("BgElevated")
        coreNode.strokeColor = uiColor("BrandOrange").withAlphaComponent(0.5)
        coreNode.lineWidth = 2
        background.applyTraits(traits)
        lockedDirty = true
        shownCharge = -1

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
        background.update(deltaTime: delta)
        effects.updateDanger(engine.dangerLevel, pulse: currentTime)

        for event in engine.drainEvents() {
            handle(event)
            onEvent?(event)
        }

        turnWell(deltaTime: delta)
        renderActivePiece()
        if lockedDirty {
            renderLockedCells()
            lockedDirty = false
        }
        renderCharge(time: currentTime)
        onFrame?()
    }

    /// Eases the well round so the shard's sector sits at the top.
    private func turnWell(deltaTime: TimeInterval) {
        let sector = engine.current?.centreSector ?? Double(engine.aim)
        let target = WellGeometry.rotation(bringingToTop: sector)
        let turn = WellGeometry.shortestTurn(from: rotation, to: target)
        let ease = reduceMotion ? 1 : 1 - CGFloat(exp(-deltaTime * 22))
        rotation += abs(turn) < 0.002 ? turn : turn * ease
        wellNode.zRotation = rotation
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

    /// Draws the pulse charge as an arc round the core, glowing once full.
    private func renderCharge(time: TimeInterval) {
        let fraction = engine.chargeFraction
        let full = fraction >= 1
        if fraction != shownCharge {
            shownCharge = fraction
            let path = CGMutablePath()
            if fraction > 0 {
                path.addArc(center: .zero, radius: WellGeometry.coreRadius - 10,
                            startAngle: .pi / 2, endAngle: .pi / 2 - CGFloat(fraction) * 2 * .pi,
                            clockwise: true)
            }
            chargeNode.path = path
            chargeNode.strokeColor = uiColor(full ? "BrandAmber" : "BrandOrange")
            chargeNode.lineWidth = 6
        }
        guard full, !reduceMotion else {
            chargeNode.glowWidth = 0
            coreNode.glowWidth = 0
            return
        }
        let breathing = CGFloat(0.5 + 0.5 * sin(time * 5))
        chargeNode.glowWidth = 2 + 4 * breathing
        coreNode.glowWidth = 3 * breathing
    }

    private func glyph(_ color: ShardColor) -> String? {
        colorBlindMode ? color.accessibilityGlyph : nil
    }

    // MARK: Reacting to engine events

    private func handle(_ event: GameEvent) {
        switch event {
        case let .hardDropped(rings, from, piece):
            guard rings > 0 else { break }
            let top = WellGeometry.centre.y + WellGeometry.midRadius(depth: max(from, Board.bufferRings))
            let bottom = WellGeometry.centre.y + WellGeometry.midRadius(depth: piece.origin.y)
            effects.dropTrail(centreX: WellGeometry.centre.x, width: 30,
                              fromY: top, toY: bottom, color: uiColor(piece.color.colorName))
            shake(by: 2)

        case .locked:
            lockedDirty = true
            effects.flash(color: .white, intensity: 0.18, duration: 0.1)

        case let .cleared(cells, colors, outcome):
            lockedDirty = true
            presentClear(cells: cells, colors: colors, outcome: outcome)

        case let .pulsed(cells, _):
            lockedDirty = true
            effects.burst(at: cells.map { WellGeometry.position(of: $0, rotation: rotation) },
                          colors: cells.map { _ in uiColor("BrandAmber") },
                          centre: WellGeometry.centre, big: true)
            effects.pulseWave(at: WellGeometry.centre, radius: WellGeometry.coreRadius,
                              color: uiColor("BrandAmber"))
            effects.flash(color: uiColor("BrandAmber"), intensity: 0.4, duration: 0.4)
            shake(by: 6)

        case .levelUp:
            background.pulseWarmth()
            effects.flash(color: uiColor("BrandAmber"), intensity: 0.3, duration: 0.5)

        case .coreCharged:
            effects.chainRing(at: WellGeometry.centre, radius: WellGeometry.coreRadius,
                              color: uiColor("BrandAmber"))

        case .spawned:
            lockedDirty = true

        case .gameOver:
            // Drawn here rather than left to the flag below: rendering
            // recycles the nodes, which would cancel the collapse that is
            // about to run on them.
            renderLockedCells()
            lockedDirty = false
            playGameOverCollapse()

        case .moved, .rotated, .softDropped, .rotationFailed, .pulseRejected:
            break
        }
    }

    private func presentClear(cells: [Point], colors: [ShardColor], outcome: ClearOutcome) {
        effects.burst(at: cells.map { WellGeometry.position(of: $0, rotation: rotation) },
                      colors: colors.map { uiColor($0.colorName) },
                      centre: WellGeometry.centre, big: outcome.rings > 1 || outcome.chain > 1)

        let closed = Set(cells.map(\.y)).filter { y in cells.filter { $0.y == y }.count == Board.sectors }
        for y in closed {
            effects.ringFlare(radius: WellGeometry.midRadius(depth: y),
                              width: WellGeometry.outerRadius(depth: y) - WellGeometry.innerRadius(depth: y),
                              centre: WellGeometry.centre, color: .white)
        }

        if outcome.chain > 1 {
            effects.chainRing(at: WellGeometry.centre, radius: WellGeometry.coreRadius,
                              color: uiColor("PieceT"))
            shake(by: 4 + CGFloat(min(outcome.chain, 4)))
        } else {
            shake(by: outcome.rings > 1 ? 5 : 2)
        }
    }

    private func playGameOverCollapse() {
        guard !reduceMotion else { return }
        for (index, node) in lockedPool.active.enumerated() {
            node.run(.sequence([
                .wait(forDuration: Double(index % Board.sectors) * 0.015),
                .fadeAlpha(to: 0.3, duration: 0.25)
            ]))
        }
    }

    // MARK: Small motion helpers

    private func shake(by amount: CGFloat) {
        guard !reduceMotion else { return }
        worldNode.removeAction(forKey: "shake")
        var steps: [SKAction] = []
        for index in 0..<5 {
            let decay = amount * (1 - CGFloat(index) / 5)
            steps.append(.moveBy(x: .random(in: -decay...decay),
                                 y: .random(in: -decay...decay),
                                 duration: 0.03))
        }
        steps.append(.move(to: .zero, duration: 0.05))
        worldNode.run(.sequence(steps), withKey: "shake")
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
        if dy > deadZone * 2, abs(dy) > abs(dx) {
            engine.pulse()
            return
        }
        guard !didDrag, abs(dx) < deadZone, abs(dy) < deadZone else { return }
        let fromCentre = hypot(point.x - WellGeometry.centre.x, point.y - WellGeometry.centre.y)
        if fromCentre < WellGeometry.coreRadius + 6 {
            engine.pulse()
        } else {
            engine.rotate(clockwise: point.x > WellGeometry.centre.x)
        }
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
        for y in Board.bufferRings..<Board.rings {
            path.addEllipse(in: CGRect(x: -WellGeometry.outerRadius(depth: y),
                                       y: -WellGeometry.outerRadius(depth: y),
                                       width: WellGeometry.outerRadius(depth: y) * 2,
                                       height: WellGeometry.outerRadius(depth: y) * 2))
        }
        for x in 0..<Board.sectors {
            let theta = WellGeometry.angle(sector: CGFloat(x)) + WellGeometry.sectorAngle / 2
            path.move(to: CGPoint(x: WellGeometry.coreRadius * cos(theta),
                                  y: WellGeometry.coreRadius * sin(theta)))
            path.addLine(to: CGPoint(x: WellGeometry.rimRadius * cos(theta),
                                     y: WellGeometry.rimRadius * sin(theta)))
        }
        return path
    }
}
