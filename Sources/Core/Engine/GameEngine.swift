import Foundation

/// The rules of the game, and nothing else. No UIKit, no storage, no clock of
/// its own: the caller ticks it and drains the events it produces.
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
    /// What to go back to when the pause ends.
    private var resumePhase: GamePhase = .playing

    // MARK: Internal timers

    private var bag: RandomBag
    private var gravityAccumulator: TimeInterval = 0
    private var clearTimer: TimeInterval = 0
    private var readyTimer: TimeInterval = 0

    private var lockTimer: TimeInterval = 0
    private var lockResets = 0
    private var isGrounded = false
    private var lowestRowReached = Int.min

    private var autoShift: AutoShift

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
        self.autoShift = AutoShift(das: config.das, arr: config.arr)
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
        switch phase {
        case .ready, .playing, .clearing:
            resumePhase = phase
            phase = .paused
            releaseAllInput()
        case .paused, .over:
            break
        }
    }

    func resume() {
        guard phase == .paused else { return }
        phase = resumePhase
        // The accumulator was filled by the frame the player paused on, and
        // spending it now would drop the piece the instant play resumes.
        gravityAccumulator = 0
    }

    // MARK: Frame update

    func update(deltaTime: TimeInterval) {
        // The run clock covers the clear animation too, otherwise an Ultra
        // round lasts three minutes plus however long the player spent
        // watching rows disappear.
        switch phase {
        case .playing, .clearing:
            elapsed += deltaTime
            if let remaining = timeRemaining, remaining <= 0 {
                finish(.timeUp)
                return
            }
        case .ready, .paused, .over:
            break
        }

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
        apply(autoShift.setDirection(direction))
    }

    private func updateHorizontalRepeat(deltaTime: TimeInterval) {
        apply(autoShift.tick(deltaTime: deltaTime))
    }

    private func apply(_ shift: AutoShift.Shift) {
        switch shift {
        case .stay:
            break
        case let .step(amount):
            let direction = amount > 0 ? 1 : -1
            for _ in 0..<abs(amount) where !move(dx: direction) { return }
        case let .slam(direction):
            while move(dx: direction) {}
        }
    }

    func setSoftDrop(_ active: Bool) {
        guard softDropping != active else { return }
        softDropping = active
        gravityAccumulator = 0
    }

    private func releaseAllInput() {
        autoShift.release()
        softDropping = false
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
        events.append(.hardDropped(rows: rows, from: piece.origin.y, piece: landed))
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
        // A swap into a blocked spawn ends the run; that is the only thing
        // worth announcing.
        if case .over = phase { return }
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
        autoShift.carryOverToNextPiece()
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
        events.append(.locked(piece: piece))

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
