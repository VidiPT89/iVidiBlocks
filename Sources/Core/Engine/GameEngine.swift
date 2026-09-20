import Foundation

/// Tunables the player can change in Settings. Passed in so the engine stays
/// free of any storage or UI dependency.
struct GameConfig {
    var das: TimeInterval = 0.133
    var arr: TimeInterval = 0.033
    var ghostEnabled: Bool = true
    var startLevel: Int = 1

    static let `default` = GameConfig()
}

/// Something worth reacting to, drained by the renderer once per frame.
enum GameEvent: Equatable {
    case spawned
    case moved
    case rotated(kicked: Bool)
    case rotationFailed
    case softDropped(rows: Int)
    case hardDropped(rows: Int, from: Int)
    case locked(cells: [Point])
    case linesCleared(rows: [Int], outcome: ClearOutcome)
    case levelUp(Int)
    case holdSwapped
    case holdRejected
    case gameOver(reason: GameOverReason)
}

extension GameOverReason: Equatable {}

enum GamePhase: Equatable {
    case ready
    case playing
    /// Gravity is frozen while completed rows play their clear animation.
    case clearing
    case paused
    case over(GameOverReason)
}

/// Accumulated counters for one run, folded into lifetime stats at the end.
struct RunStats {
    var piecesPlaced = 0
    var linesCleared = 0
    var tetrises = 0
    var tSpins = 0
    var maxCombo = 0
}

final class GameEngine {

    // MARK: Configuration

    let mode: GameMode
    var config: GameConfig

    // MARK: Observable state

    private(set) var board = Board()
    private(set) var current: Piece?
    private(set) var ghost: Piece?
    private(set) var holdPiece: TetrominoType?
    private(set) var preview: [TetrominoType] = []
    private(set) var phase: GamePhase = .ready

    private(set) var score = 0
    private(set) var lines = 0
    private(set) var level: Int
    private(set) var combo = -1
    private(set) var backToBack = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var stats = RunStats()

    /// Rows waiting for their clear animation to finish.
    private(set) var pendingClearRows: [Int] = []

    private var events: [GameEvent] = []

    // MARK: Internal timers

    private var bag: RandomBag
    private var gravityAccumulator: TimeInterval = 0
    private var clearTimer: TimeInterval = 0
    private var readyTimer: TimeInterval = 0

    private var lockTimer: TimeInterval = 0
    private var lockResets = 0
    private var isGrounded = false
    private var lowestRowReached = Int.min

    private var horizontalDirection: Int = 0
    private var dasTimer: TimeInterval = 0
    private var dasCharged = false
    private var arrTimer: TimeInterval = 0

    private var softDropping = false
    private var holdUsedThisPiece = false
    private var lastActionWasRotation = false
    private var lastKickIndex = 0

    static let lockDelay: TimeInterval = 0.5
    static let maxLockResets = 15
    static let clearDuration: TimeInterval = 0.35
    static let readyDuration: TimeInterval = 1.2

    // MARK: Lifecycle

    /// - Parameter board: a pre-filled playfield, used to resume a saved
    ///   game and to set up specific situations in the tests.
    init(mode: GameMode,
         config: GameConfig = .default,
         random: PieceRandomSource = SystemPieceRandom(),
         board: Board = Board()) {
        self.mode = mode
        self.config = config
        self.level = config.startLevel
        self.bag = RandomBag(random: random)
        self.board = board
        self.preview = bag.preview
        self.readyTimer = GameEngine.readyDuration
    }

    /// Skips the countdown. Tests call this to start playing immediately.
    func startImmediately() {
        readyTimer = 0
        phase = .playing
        spawnNextPiece()
    }

    func drainEvents() -> [GameEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    // MARK: Time remaining / progress

    var timeRemaining: TimeInterval? {
        guard let limit = mode.timeLimit else { return nil }
        return max(0, limit - elapsed)
    }

    var linesRemaining: Int? {
        guard let target = mode.lineTarget else { return nil }
        return max(0, target - lines)
    }

    /// How close the stack is to the ceiling, 0...1, for the danger vignette.
    var dangerLevel: Double {
        guard let top = board.highestOccupiedRow() else { return 0 }
        let visibleTop = Board.bufferRows
        let dangerZone = 6.0
        let depth = Double(top - visibleTop)
        guard depth < dangerZone else { return 0 }
        return min(1, (dangerZone - depth) / dangerZone)
    }

    // MARK: Pausing

    func pause() {
        guard phase == .playing || phase == .clearing else { return }
        phase = .paused
        releaseAllInput()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = pendingClearRows.isEmpty ? .playing : .clearing
    }

    // MARK: Frame update

    func update(deltaTime: TimeInterval) {
        switch phase {
        case .ready:
            readyTimer -= deltaTime
            if readyTimer <= 0 {
                phase = .playing
                spawnNextPiece()
            }
        case .clearing:
            clearTimer -= deltaTime
            if clearTimer <= 0 { finishLineClear() }
        case .playing:
            elapsed += deltaTime
            if let remaining = timeRemaining, remaining <= 0 {
                finish(.timeUp)
                return
            }
            updateHorizontalRepeat(deltaTime: deltaTime)
            updateGravity(deltaTime: deltaTime)
            updateLockDelay(deltaTime: deltaTime)
        case .paused, .over:
            break
        }
    }

    private func updateGravity(deltaTime: TimeInterval) {
        guard current != nil else { return }
        var interval = ScoreCalculator.gravityInterval(level: level)
        if softDropping {
            interval = max(interval / 20, 0.02)
        }

        gravityAccumulator += deltaTime
        var droppedRows = 0
        while gravityAccumulator >= interval {
            gravityAccumulator -= interval
            guard let moving = current, board.canPlace(moving.moved(dx: 0, dy: 1)) else {
                gravityAccumulator = 0
                break
            }
            setCurrent(moving.moved(dx: 0, dy: 1))
            droppedRows += 1
        }

        if droppedRows > 0 {
            lastActionWasRotation = false
            if softDropping {
                score += ScoreCalculator.softDropPoints(rows: droppedRows)
                events.append(.softDropped(rows: droppedRows))
            }
        }
    }

    private func updateLockDelay(deltaTime: TimeInterval) {
        guard let piece = current else { return }
        let grounded = !board.canPlace(piece.moved(dx: 0, dy: 1))

        if grounded {
            if !isGrounded {
                isGrounded = true
                lockTimer = GameEngine.lockDelay
            }
            lockTimer -= deltaTime
            if lockTimer <= 0 || lockResets >= GameEngine.maxLockResets {
                lockCurrentPiece()
            }
        } else {
            isGrounded = false
            lockTimer = GameEngine.lockDelay
        }
    }

    /// Any successful move or rotation buys the player more time on the
    /// floor, but only up to `maxLockResets` so a piece cannot hover forever.
    private func registerLockReset() {
        guard isGrounded else { return }
        guard lockResets < GameEngine.maxLockResets else { return }
        lockResets += 1
        lockTimer = GameEngine.lockDelay
    }

    // MARK: Horizontal input with DAS / ARR

    func setHorizontalInput(_ direction: Int) {
        let clamped = direction == 0 ? 0 : (direction > 0 ? 1 : -1)
        guard clamped != horizontalDirection else { return }
        horizontalDirection = clamped
        dasTimer = 0
        arrTimer = 0
        dasCharged = false
        if clamped != 0 { _ = move(dx: clamped) }
    }

    private func updateHorizontalRepeat(deltaTime: TimeInterval) {
        guard horizontalDirection != 0 else { return }

        if !dasCharged {
            dasTimer += deltaTime
            if dasTimer >= config.das {
                dasCharged = true
                arrTimer = 0
                // ARR of zero means slide straight to the wall.
                if config.arr <= 0 {
                    while move(dx: horizontalDirection) {}
                }
            }
            return
        }

        guard config.arr > 0 else {
            while move(dx: horizontalDirection) {}
            return
        }

        arrTimer += deltaTime
        while arrTimer >= config.arr {
            arrTimer -= config.arr
            if !move(dx: horizontalDirection) { break }
        }
    }

    func setSoftDrop(_ active: Bool) {
        guard softDropping != active else { return }
        softDropping = active
        gravityAccumulator = 0
    }

    private func releaseAllInput() {
        horizontalDirection = 0
        softDropping = false
        dasCharged = false
        dasTimer = 0
        arrTimer = 0
    }

    // MARK: Player actions

    @discardableResult
    func move(dx: Int) -> Bool {
        guard phase == .playing, let piece = current else { return false }
        let candidate = piece.moved(dx: dx, dy: 0)
        guard board.canPlace(candidate) else { return false }
        setCurrent(candidate)
        lastActionWasRotation = false
        registerLockReset()
        events.append(.moved)
        return true
    }

    @discardableResult
    func rotate(clockwise: Bool) -> Bool {
        guard phase == .playing, let piece = current else { return false }
        guard let result = RotationSystem.rotate(piece, clockwise: clockwise, on: board) else {
            events.append(.rotationFailed)
            return false
        }
        setCurrent(result.piece)
        lastActionWasRotation = true
        lastKickIndex = result.kickIndex
        registerLockReset()
        events.append(.rotated(kicked: result.kickIndex != 0))
        return true
    }

    func hardDrop() {
        guard phase == .playing, let piece = current else { return }
        let landed = board.hardDropPosition(of: piece)
        let rows = landed.origin.y - piece.origin.y
        if rows > 0 {
            score += ScoreCalculator.hardDropPoints(rows: rows)
            lastActionWasRotation = false
        }
        setCurrent(landed)
        events.append(.hardDropped(rows: rows, from: piece.origin.y))
        lockCurrentPiece()
    }

    func hold() {
        guard phase == .playing, let piece = current else { return }
        guard !holdUsedThisPiece else {
            events.append(.holdRejected)
            return
        }
        holdUsedThisPiece = true
        let outgoing = piece.type

        if let stored = holdPiece {
            holdPiece = outgoing
            spawn(type: stored)
        } else {
            holdPiece = outgoing
            spawnNextPiece()
        }
        events.append(.holdSwapped)
    }

    // MARK: Piece lifecycle

    private func setCurrent(_ piece: Piece) {
        current = piece
        if piece.origin.y > lowestRowReached {
            lowestRowReached = piece.origin.y
            lockResets = 0
        }
        recomputeGhost()
    }

    private func recomputeGhost() {
        guard config.ghostEnabled, let piece = current else {
            ghost = nil
            return
        }
        let landed = board.hardDropPosition(of: piece)
        ghost = landed.origin == piece.origin ? nil : landed
    }

    private func spawnNextPiece() {
        let type = bag.next()
        preview = bag.preview
        spawn(type: type)
    }

    private func spawn(type: TetrominoType) {
        let originX: Int
        switch type {
        case .o: originX = 4
        default: originX = 3
        }
        var piece = Piece(type: type, state: .spawn, origin: Point(x: originX, y: 0))

        guard board.canPlace(piece) else {
            finish(.topOut)
            return
        }
        // Pieces appear in the buffer then immediately step into view.
        if board.canPlace(piece.moved(dx: 0, dy: 1)) {
            piece = piece.moved(dx: 0, dy: 1)
        }

        lowestRowReached = piece.origin.y
        lockResets = 0
        lockTimer = GameEngine.lockDelay
        isGrounded = false
        gravityAccumulator = 0
        lastActionWasRotation = false
        lastKickIndex = 0

        setCurrent(piece)
        events.append(.spawned)

        // Re-apply a held direction so the piece keeps sliding on respawn.
        if horizontalDirection != 0 && dasCharged {
            arrTimer = config.arr
        }
    }

    private func lockCurrentPiece() {
        guard let piece = current else { return }

        let spin = SpinDetector.detect(piece: piece,
                                       lastActionWasRotation: lastActionWasRotation,
                                       kickIndex: lastKickIndex,
                                       board: board)

        board.lock(piece)
        stats.piecesPlaced += 1
        current = nil
        ghost = nil
        holdUsedThisPiece = false
        isGrounded = false
        events.append(.locked(cells: piece.cells))

        // Lock out: the whole piece finished above the visible playfield.
        if piece.cells.allSatisfy({ $0.y < Board.bufferRows }) {
            finish(.topOut)
            return
        }

        let completed = board.completedRows()
        resolveScore(rows: completed, spin: spin)

        if completed.isEmpty {
            spawnNextPiece()
        } else {
            pendingClearRows = completed
            clearTimer = GameEngine.clearDuration
            phase = .clearing
        }
    }

    private func resolveScore(rows: [Int], spin: SpinKind) {
        let cleared = rows.count

        if cleared > 0 {
            combo += 1
        } else {
            combo = -1
        }
        let activeCombo = max(combo, 0)
        stats.maxCombo = max(stats.maxCombo, activeCombo)

        // A perfect clear is judged on the board as it will look once the
        // completed rows are gone.
        var projected = board
        projected.clearRows(rows)
        let perfect = cleared > 0 && projected.isEmpty()

        let difficult = cleared == 4 || (spin != .none && cleared > 0)
        let chained = difficult && backToBack

        let points = ScoreCalculator.points(lines: cleared,
                                            spin: spin,
                                            perfectClear: perfect,
                                            level: level,
                                            backToBack: chained,
                                            combo: activeCombo)
        score += points

        if difficult {
            backToBack = true
        } else if cleared > 0 {
            backToBack = false
        }

        if cleared == 4 { stats.tetrises += 1 }
        if spin != .none { stats.tSpins += 1 }

        guard cleared > 0 else { return }

        let outcome = ClearOutcome(lines: cleared,
                                   spin: spin,
                                   perfectClear: perfect,
                                   backToBack: chained,
                                   combo: activeCombo,
                                   points: points)
        events.append(.linesCleared(rows: rows, outcome: outcome))
    }

    private func finishLineClear() {
        let rows = pendingClearRows
        pendingClearRows = []
        board.clearRows(rows)

        lines += rows.count
        stats.linesCleared += rows.count

        if mode.levelsUp {
            let newLevel = ScoreCalculator.level(forTotalLines: lines,
                                                 startingAt: config.startLevel)
            if newLevel > level {
                level = newLevel
                events.append(.levelUp(level))
            }
        }

        if let target = mode.lineTarget, lines >= target {
            finish(.targetReached)
            return
        }

        phase = .playing
        spawnNextPiece()
    }

    private func finish(_ reason: GameOverReason) {
        if case .over = phase { return }
        phase = .over(reason)
        current = nil
        ghost = nil
        releaseAllInput()
        events.append(.gameOver(reason: reason))
    }
}
