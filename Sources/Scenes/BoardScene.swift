import SpriteKit
import UIKit

/// Renders the playfield and turns raw touches into engine input. The scene
/// owns the frame clock: it ticks the engine, then draws whatever the engine
/// says is true. It never decides any rule itself.
final class BoardScene: SKScene {

    /// Logical units. The view scales this to fit, so the layout is identical
    /// on every device and nothing has to be recomputed on rotation.
    static let cellSize: CGFloat = 32
    static let visibleRows = Board.rows - Board.bufferRows
    static let boardSize = CGSize(width: cellSize * CGFloat(Board.columns),
                                  height: cellSize * CGFloat(visibleRows))

    var engine: GameEngine
    var onEvent: ((GameEvent) -> Void)?
    /// Fired after every tick so the HUD can pull fresh numbers.
    var onFrame: (() -> Void)?
    var colorBlindMode = false { didSet { lockedDirty = true } }
    var reduceMotion = false {
        didSet { effects.reduceMotion = reduceMotion }
    }

    private let worldNode = SKNode()
    private let gridNode = SKSpriteNode()
    private let lockedLayer = SKNode()
    private let ghostLayer = SKNode()
    private let pieceLayer = SKNode()
    private let effects: EffectsLayer
    private let background: BackgroundLayer

    private var lockedPool: BlockPool!
    private var ghostPool: BlockPool!
    private var piecePool: BlockPool!

    private var lastUpdate: TimeInterval = 0
    private var lockedDirty = true
    private var traits: UITraitCollection
    /// The piece from the most recent lock, so effects that belong to it can
    /// still be placed after the engine has moved on.
    private var lastLocked: Piece?

    // Gesture bookkeeping
    private var touchStart: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var lastDragColumn = 0
    private var didDrag = false
    private var isSoftDropping = false

    private let deadZone = cellSize * 0.28
    private let hardDropVelocity: CGFloat = cellSize * 26

    init(engine: GameEngine, traits: UITraitCollection) {
        self.engine = engine
        self.traits = traits
        self.effects = EffectsLayer(cellSize: Self.cellSize, boardSize: Self.boardSize)
        self.background = BackgroundLayer(boardSize: Self.boardSize, traits: traits)
        super.init(size: Self.boardSize)

        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        guard worldNode.parent == nil else { return }
        addChild(worldNode)

        gridNode.anchorPoint = .zero
        gridNode.zPosition = -5

        lockedLayer.zPosition = 1
        ghostLayer.zPosition = 0
        pieceLayer.zPosition = 2
        effects.zPosition = 10

        for node in [background, gridNode, ghostLayer, lockedLayer, pieceLayer, effects] as [SKNode] {
            worldNode.addChild(node)
        }

        lockedPool = BlockPool(parent: lockedLayer, cellSize: Self.cellSize)
        ghostPool = BlockPool(parent: ghostLayer, cellSize: Self.cellSize)
        piecePool = BlockPool(parent: pieceLayer, cellSize: Self.cellSize)

        applyTraits(traits)
    }

    // MARK: Theme

    func applyTraits(_ traits: UITraitCollection) {
        self.traits = traits
        BlockTextureFactory.invalidate()
        gridNode.texture = BoardScene.gridTexture(traits: traits)
        gridNode.size = Self.boardSize
        background.applyTraits(traits)
        lockedDirty = true

        // Recolour rather than rebuild, so a theme switch never interrupts play.
        worldNode.alpha = 0.85
        worldNode.run(.fadeAlpha(to: 1, duration: 0.25))
    }

    // MARK: Coordinates

    private func position(column x: Int, row y: Int) -> CGPoint {
        let visibleRow = y - Board.bufferRows
        return CGPoint(x: (CGFloat(x) + 0.5) * Self.cellSize,
                       y: Self.boardSize.height - (CGFloat(visibleRow) + 0.5) * Self.cellSize)
    }

    private func rowCentreY(_ y: Int) -> CGFloat {
        position(column: 0, row: y).y
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval
        if lastUpdate == 0 {
            delta = 1.0 / 60.0
        } else {
            // Clamp so a stall (backgrounding, a long frame) never teleports
            // the piece down the board.
            delta = min(currentTime - lastUpdate, 1.0 / 20.0)
        }
        lastUpdate = currentTime

        engine.update(deltaTime: delta)
        background.update(deltaTime: delta)
        effects.updateDanger(engine.dangerLevel, pulse: currentTime)

        for event in engine.drainEvents() {
            handle(event)
            onEvent?(event)
        }

        renderActivePiece()
        if lockedDirty {
            renderLockedBlocks()
            lockedDirty = false
        }
        onFrame?()
    }

    // MARK: Rendering

    private func renderLockedBlocks() {
        lockedPool.recycleAll()
        let clearing = Set(engine.pendingClearRows)

        for y in Board.bufferRows..<Board.rows {
            for x in 0..<Board.columns {
                guard let type = engine.board[x, y] else { continue }
                let node = lockedPool.obtain()
                node.configure(type: type, cellSize: Self.cellSize, style: .solid,
                               glyph: colorBlindMode, traits: traits)
                node.position = position(column: x, row: y)
                if clearing.contains(y) {
                    node.colorBlendFactor = 0.7
                    node.color = .white
                }
            }
        }
    }

    private func renderActivePiece() {
        piecePool.recycleAll()
        ghostPool.recycleAll()

        if let ghost = engine.ghost {
            for cell in ghost.cells where cell.y >= Board.bufferRows {
                let node = ghostPool.obtain()
                node.configure(type: ghost.type, cellSize: Self.cellSize, style: .ghost,
                               glyph: false, traits: traits)
                node.position = position(column: cell.x, row: cell.y)
            }
        }

        guard let piece = engine.current else { return }
        for cell in piece.cells where cell.y >= Board.bufferRows {
            let node = piecePool.obtain()
            node.configure(type: piece.type, cellSize: Self.cellSize, style: .solid,
                           glyph: colorBlindMode, traits: traits)
            node.position = position(column: cell.x, row: cell.y)
        }
    }

    // MARK: Reacting to engine events

    private func handle(_ event: GameEvent) {
        switch event {
        case let .rotated(kicked):
            bumpPiece(scale: 1.06)
            if kicked, let piece = engine.current {
                let edge = piece.cells.map(\.x).min() ?? 0
                effects.wallSpark(at: position(column: edge, row: piece.cells[0].y),
                                  color: uiColor("BrandAmber"))
            }

        case let .hardDropped(rows, fromY, piece):
            guard rows > 0 else { break }
            let xs = piece.cells.map(\.x)
            let minX = xs.min() ?? 0
            let width = (xs.max() ?? 0) - minX + 1
            effects.hardDropTrail(column: minX, width: width,
                                  fromY: rowCentreY(max(fromY, Board.bufferRows)),
                                  toY: rowCentreY(piece.cells.map(\.y).max() ?? 0),
                                  color: uiColor(piece.type.colorName))
            squashPiece()

        case let .locked(piece):
            lastLocked = piece
            lockedDirty = true
            effects.flash(color: .white, intensity: 0.22, duration: 0.1)

        case let .linesCleared(rows, outcome):
            lockedDirty = true
            presentClear(rows: rows, outcome: outcome)

        case .levelUp:
            background.pulseWarmth()
            effects.flash(color: uiColor("BrandAmber"), intensity: 0.3, duration: 0.5)

        case .spawned, .holdSwapped:
            lockedDirty = true

        case .gameOver:
            // Drawn here rather than left to the flag below: rendering
            // recycles the nodes, which would cancel the collapse that is
            // about to run on them.
            renderLockedBlocks()
            lockedDirty = false
            playGameOverCollapse()

        case .moved, .softDropped, .rotationFailed, .holdRejected:
            break
        }
    }

    private func presentClear(rows: [Int], outcome: ClearOutcome) {
        let colors = rows.map { y in
            (0..<Board.columns).map { x in
                uiColor(engine.board[x, y]?.colorName ?? "BrandOrange")
            }
        }
        effects.lineClear(rows: rows.map(rowCentreY), colors: colors,
                          isTetris: outcome.lines == 4)

        if outcome.lines == 4 {
            effects.flash(color: uiColor("BrandOrange"), intensity: 0.45, duration: 0.35)
            shake(by: 6)
        } else {
            shake(by: 2)
        }

        // The spin belongs to the piece that just locked, which the engine has
        // already let go of, so the ring is centred on the remembered one.
        if outcome.spin != .none, let piece = lastLocked {
            effects.spinRing(at: position(column: piece.origin.x + 1, row: piece.origin.y + 1),
                             color: uiColor("PieceT"))
        }

        if outcome.perfectClear {
            effects.perfectClearSweep(color: uiColor("BrandAmber"))
        }
    }

    private func playGameOverCollapse() {
        guard !reduceMotion else { return }
        for (index, node) in lockedLayer.children.enumerated() where !node.isHidden {
            let delay = Double(index % Board.columns) * 0.012
                + Double(index / Board.columns) * 0.03
            node.run(.sequence([
                .wait(forDuration: delay),
                .group([.colorize(with: .black, colorBlendFactor: 0.75, duration: 0.25),
                        .fadeAlpha(to: 0.35, duration: 0.25)])
            ]))
        }
    }

    // MARK: Small motion helpers

    private func bumpPiece(scale: CGFloat) {
        guard !reduceMotion else { return }
        pieceLayer.removeAllActions()
        pieceLayer.setScale(1)
        pieceLayer.run(.sequence([.scale(to: scale, duration: 0.05),
                                  .scale(to: 1, duration: 0.07)]))
    }

    private func squashPiece() {
        guard !reduceMotion else { return }
        pieceLayer.removeAllActions()
        pieceLayer.yScale = 1
        pieceLayer.run(.sequence([.scaleY(to: 0.88, duration: 0.04),
                                  .scaleY(to: 1, duration: 0.09)]))
        shake(by: 2)
    }

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
        lastDragColumn = 0
        didDrag = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let dx = point.x - touchStart.x
        let dy = point.y - touchStart.y

        if abs(dx) > abs(dy) {
            let columns = Int((dx / Self.cellSize).rounded(.towardZero))
            if columns != lastDragColumn {
                let steps = columns - lastDragColumn
                for _ in 0..<abs(steps) { engine.move(dx: steps > 0 ? 1 : -1) }
                lastDragColumn = columns
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

        if dy < -deadZone, verticalSpeed > hardDropVelocity, abs(dy) > abs(dx) {
            engine.hardDrop()
            return
        }
        if dy > deadZone * 2, abs(dy) > abs(dx) {
            engine.hold()
            return
        }
        if !didDrag, abs(dx) < deadZone, abs(dy) < deadZone {
            engine.rotate(clockwise: point.x > Self.boardSize.width / 2)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isSoftDropping {
            isSoftDropping = false
            engine.setSoftDrop(false)
        }
    }

    // MARK: Grid

    private static func gridTexture(traits: UITraitCollection) -> SKTexture {
        let size = boardSize
        let line = UIColor(named: "GridLine", in: .main, compatibleWith: traits)
            ?? UIColor.white.withAlphaComponent(0.06)

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(line.cgColor)
            cg.setLineWidth(1)
            for column in 0...Board.columns {
                let x = CGFloat(column) * cellSize
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...visibleRows {
                let y = CGFloat(row) * cellSize
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
            }
            cg.strokePath()
        }
        return SKTexture(image: image)
    }
}
