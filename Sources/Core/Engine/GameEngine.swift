import Foundation

/// The rules of the game, and nothing else. No UIKit, no storage, no clock of
/// its own: the caller ticks it and drains the events it produces.
final class GameEngine {

    // MARK: Configuration

    let mode: GameMode
    let config: GameConfig

    // MARK: Observable state

    private(set) var board = Board()
    private(set) var current: Piece?
    private(set) var ghost: Piece?
    private(set) var preview: [Shard] = []
    private(set) var phase: GamePhase = .ready
    /// The sector at the top of the screen. New shards enter here, so the
    /// well never snaps back between pieces.
    private(set) var aim = 0

    private(set) var score = 0
    /// Cells cleared by rings, arcs and pulses. Drives levels and Target.
    private(set) var shards = 0
    private(set) var level: Int
    /// Link of the cascade currently clearing, 0 when nothing is.
    private(set) var chain = 0
    /// Cleared cells banked towards the next pulse, up to `pulseCost`.
    private(set) var charge = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var stats = RunStats()
    /// Shards drawn from the bag so far.
    private(set) var piecesDealt = 0

    /// Cells waiting for their clear animation to finish.
    private(set) var pendingClear: [Point] = []

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
    private var lowestRingReached = Int.min

    private var autoShift: AutoShift
    private var softDropping = false

    static let lockDelay: TimeInterval = 0.5
    static let maxLockResets = 15
    static let clearDuration: TimeInterval = 0.35
    static let readyDuration: TimeInterval = 1.2
    static let pulseCost = 32
    /// How many of the innermost rings a pulse wipes.
    static let pulseRings = 2

    // MARK: Lifecycle

    /// - Parameter board: a pre-filled well, used to restore a saved run, to
    ///   set up practice drills and to build specific situations in tests.
    init(mode: GameMode,
         config: GameConfig = .default,
         random: PieceRandomSource = SystemPieceRandom(),
         board: Board = Board(),
         charge: Int = 0) {
        self.mode = mode
        self.config = config
        self.level = config.startLevel
        self.autoShift = AutoShift(das: config.das, arr: config.arr)
        self.bag = RandomBag(random: random)
        self.board = board
        self.charge = min(max(charge, 0), GameEngine.pulseCost)
        self.preview = bag.preview
        self.readyTimer = GameEngine.readyDuration
    }

    /// Brings a saved run back on its pause screen, or returns `nil` when the
    /// snapshot could not have come from a legal game.
    convenience init?(restoring saved: GameSnapshot,
                      config: GameConfig = .default,
                      random: PieceRandomSource = SystemPieceRandom()) {
        let mode = saved.mode
        let expectedLevel = mode.levelsUp
            ? ScoreCalculator.level(forTotalShards: saved.shards, startingAt: saved.startLevel)
            : saved.startLevel
        guard saved.version == GameSnapshot.currentVersion,
              let board = Board(cells: saved.cells),
              saved.startLevel >= 1, saved.level == expectedLevel,
              saved.score >= 0, saved.shards >= 0,
              saved.shards < mode.shardTarget ?? .max,
              (0...GameEngine.pulseCost).contains(saved.charge),
              (0..<Board.sectors).contains(saved.aim),
              saved.elapsed.isFinite, saved.elapsed >= 0,
              saved.elapsed < mode.timeLimit ?? .infinity,
              (0...GameEngine.maxLockResets).contains(saved.lockResets) else { return nil }

        if saved.pendingClear.isEmpty {
            guard saved.chain == 0, let piece = saved.current, board.canPlace(piece) else { return nil }
        } else {
            guard saved.current == nil, saved.chain >= 1,
                  Set(saved.pendingClear) == board.scan().cells else { return nil }
        }

        var restoredConfig = config
        restoredConfig.startLevel = saved.startLevel
        self.init(mode: mode, config: restoredConfig, random: random,
                  board: board, charge: saved.charge)

        bag = RandomBag(queue: saved.queue, random: random)
        preview = bag.preview
        aim = saved.aim
        pendingClear = saved.pendingClear
        chain = saved.chain
        score = saved.score
        shards = saved.shards
        level = saved.level
        elapsed = saved.elapsed
        stats = saved.stats
        lockResets = saved.lockResets
        lowestRingReached = saved.lowestRingReached
        clearTimer = GameEngine.clearDuration
        readyTimer = 0
        current = saved.current
        recomputeGhost()

        resumePhase = saved.pendingClear.isEmpty ? .playing : .clearing
        phase = .paused
    }

    /// The run as it stands, or `nil` before the first shard and after the
    /// end, when there is nothing worth coming back to.
    func snapshot() -> GameSnapshot? {
        switch phase == .paused ? resumePhase : phase {
        case .playing, .clearing: break
        case .ready, .paused, .over: return nil
        }
        return GameSnapshot(mode: mode,
                            startLevel: config.startLevel,
                            cells: board.cells,
                            current: current,
                            aim: aim,
                            queue: bag.queue,
                            pendingClear: pendingClear,
                            chain: chain,
                            charge: charge,
                            score: score,
                            shards: shards,
                            level: level,
                            elapsed: elapsed,
                            stats: stats,
                            lockResets: lockResets,
                            lowestRingReached: lowestRingReached)
    }

    /// Skips the countdown. Tests call this to start playing immediately.
    func startImmediately() {
        guard phase == .ready else { return }
        readyTimer = 0
        phase = .playing
        spawnNextPiece()
    }

    func drainEvents() -> [GameEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    var canPulse: Bool {
        phase == .playing && current != nil && charge >= GameEngine.pulseCost
    }

    /// Pulse charge as a fraction, for the core meter.
    var chargeFraction: Double {
        Double(charge) / Double(GameEngine.pulseCost)
    }

    // MARK: Time remaining / progress

    var timeRemaining: TimeInterval? {
        guard let limit = mode.timeLimit else { return nil }
        return max(0, limit - elapsed)
    }

    var shardsRemaining: Int? {
        guard let target = mode.shardTarget else { return nil }
        return max(0, target - shards)
    }

    /// How close the stack is to the rim, 0...1, for the danger vignette.
    var dangerLevel: Double {
        guard let outer = board.outermostOccupiedRing() else { return 0 }
        let dangerZone = 3.0
        let depth = Double(outer - Board.bufferRings)
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
        // spending it now would drop the shard the instant play resumes.
        gravityAccumulator = 0
    }

    // MARK: Frame update

    func update(deltaTime: TimeInterval, clockDeltaTime: TimeInterval? = nil) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let clockDelta = clockDeltaTime ?? deltaTime
        guard clockDelta.isFinite, clockDelta >= 0 else { return }
        // The run clock covers the clear animation too, otherwise a Blitz
        // round lasts two minutes plus however long the player spent
        // watching cascades.
        switch phase {
        case .playing, .clearing:
            elapsed = min(elapsed + clockDelta, mode.timeLimit ?? .infinity)
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
            if clearTimer <= 0 { finishClear() }
        case .playing:
            apply(autoShift.tick(deltaTime: deltaTime))
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
            interval = min(interval, max(interval / 20, 0.03))
        }

        gravityAccumulator += deltaTime
        var dropped = 0
        while gravityAccumulator >= interval {
            gravityAccumulator -= interval
            guard let moving = current, board.canPlace(moving.moved(dx: 0, dy: 1)) else {
                gravityAccumulator = 0
                break
            }
            setCurrent(moving.moved(dx: 0, dy: 1))
            dropped += 1
        }

        if dropped > 0, softDropping {
            score += ScoreCalculator.softDropPoints(rings: dropped)
            events.append(.softDropped(rings: dropped))
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

    /// Any successful move or turn buys the player more time once landed,
    /// but only up to `maxLockResets` so a shard cannot circle forever.
    private func registerLockReset() {
        guard isGrounded, lockResets < GameEngine.maxLockResets else { return }
        lockResets += 1
        lockTimer = GameEngine.lockDelay
    }

    // MARK: Sideways input with DAS / ARR

    func setHorizontalInput(_ direction: Int) {
        guard phase == .playing || phase == .clearing || direction == 0 else { return }
        apply(autoShift.setDirection(direction))
    }

    private func apply(_ shift: AutoShift.Shift) {
        switch shift {
        case .stay:
            break
        case let .step(amount):
            let direction = amount > 0 ? 1 : -1
            for _ in 0..<abs(amount) {
                guard move(dx: direction) else { return }
            }
        case let .slam(direction):
            // Without walls a slam could circle for ever; stop after one lap.
            for _ in 0..<Board.sectors {
                guard move(dx: direction) else { return }
            }
        }
    }

    func setSoftDrop(_ active: Bool) {
        guard !active || phase == .playing || phase == .clearing else { return }
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
        guard dx != 0, phase == .playing, let piece = current else { return false }
        let candidate = piece.moved(dx: dx, dy: 0)
        guard board.canPlace(candidate) else { return false }
        setCurrent(candidate)
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
        registerLockReset()
        events.append(.rotated(kicked: result.kickIndex != 0))
        return true
    }

    /// One discrete ring for assistive input, which cannot hold a touch down.
    func softDropStep() {
        guard phase == .playing, let piece = current else { return }
        let candidate = piece.moved(dx: 0, dy: 1)
        guard board.canPlace(candidate) else { return }
        setCurrent(candidate)
        score += ScoreCalculator.softDropPoints(rings: 1)
        events.append(.softDropped(rings: 1))
    }

    func hardDrop() {
        guard phase == .playing, let piece = current else { return }
        let landed = board.dropPosition(of: piece)
        let rings = landed.origin.y - piece.origin.y
        if rings > 0 { score += ScoreCalculator.hardDropPoints(rings: rings) }
        setCurrent(landed)
        events.append(.hardDropped(rings: rings, from: piece.origin.y, piece: landed))
        lockCurrentPiece()
    }

    /// Spends a full charge to wipe the innermost rings. The cells outside
    /// them slide in at once, and the falling shard is pushed back out if
    /// anything slid into its way.
    func pulse() {
        guard canPulse, var piece = current else {
            events.append(.pulseRejected)
            return
        }
        let innermost = (Board.rings - GameEngine.pulseRings)..<Board.rings
        let doomed = Set(innermost.flatMap { y in
            (0..<Board.sectors).compactMap { x in board[x, y] == nil ? nil : Point(x: x, y: y) }
        })
        guard !doomed.isEmpty else {
            events.append(.pulseRejected)
            return
        }

        charge = 0
        board.remove(doomed)
        while !board.canPlace(piece) {
            guard piece.origin.y > 0 else {
                finish(.topOut)
                return
            }
            piece = piece.moved(dx: 0, dy: -1)
        }
        setCurrent(piece)

        let points = ScoreCalculator.pulsePoints(cells: doomed.count, level: level)
        score += points
        stats.pulses += 1
        events.append(.pulsed(cells: doomed.sorted(by: Self.cellOrder), points: points))
        _ = addProgress(cells: doomed.count, chargesCore: false)
    }

    // MARK: Piece lifecycle

    private func setCurrent(_ piece: Piece) {
        current = piece
        aim = piece.origin.x
        if piece.origin.y > lowestRingReached {
            lowestRingReached = piece.origin.y
            lockResets = 0
        }
        recomputeGhost()
    }

    private func recomputeGhost() {
        guard config.ghostEnabled, let piece = current else {
            ghost = nil
            return
        }
        let landed = board.dropPosition(of: piece)
        ghost = landed.origin == piece.origin ? nil : landed
    }

    private func spawnNextPiece() {
        let shard = bag.next()
        piecesDealt += 1
        preview = bag.preview

        var piece = Piece(shard: shard, origin: Point(x: aim, y: Board.bufferRings - 1))
        guard board.canPlace(piece) else {
            finish(.topOut)
            return
        }
        // Shards appear just outside the rim, then step straight in.
        if board.canPlace(piece.moved(dx: 0, dy: 1)) {
            piece = piece.moved(dx: 0, dy: 1)
        }

        lowestRingReached = piece.origin.y
        lockResets = 0
        lockTimer = GameEngine.lockDelay
        isGrounded = false
        gravityAccumulator = 0

        setCurrent(piece)
        events.append(.spawned)
        autoShift.carryOverToNextPiece()
    }

    private func lockCurrentPiece() {
        guard let piece = current else { return }

        board.lock(piece)
        stats.piecesPlaced += 1
        current = nil
        ghost = nil
        isGrounded = false
        events.append(.locked(piece: piece))

        // Lock out: the whole shard came to rest outside the rim.
        if piece.cells.allSatisfy({ $0.y < Board.bufferRings }) {
            finish(.topOut)
            return
        }

        let scan = board.scan()
        if scan.isEmpty {
            chain = 0
            spawnNextPiece()
        } else {
            chain = 1
            beginClear(scan)
        }
    }

    private func beginClear(_ scan: ClearScan) {
        let cells = scan.cells.sorted(by: Self.cellOrder)
        let points = ScoreCalculator.points(cells: cells.count, rings: scan.rings,
                                            arcs: scan.arcs, chain: chain, level: level)
        score += points
        stats.ringsCleared += scan.rings
        stats.arcsFused += scan.arcs
        stats.maxChain = max(stats.maxChain, chain)

        let outcome = ClearOutcome(cells: cells.count, rings: scan.rings, arcs: scan.arcs,
                                   chain: chain, points: points)
        events.append(.cleared(cells: cells,
                               colors: cells.compactMap { board[$0.x, $0.y] },
                               outcome: outcome))
        pendingClear = cells
        clearTimer = GameEngine.clearDuration
        phase = .clearing
    }

    private func finishClear() {
        let cells = pendingClear
        pendingClear = []
        board.remove(Set(cells))
        guard addProgress(cells: cells.count, chargesCore: true) else { return }

        // Whatever slid inwards may have lined up into something new.
        let cascade = board.scan()
        if cascade.isEmpty {
            chain = 0
            phase = .playing
            spawnNextPiece()
        } else {
            chain += 1
            beginClear(cascade)
        }
    }

    /// Banks cleared cells towards level, target and the core.
    /// - Returns: `false` when this ended the run.
    private func addProgress(cells: Int, chargesCore: Bool) -> Bool {
        shards += cells
        stats.shardsCleared += cells

        if chargesCore, charge < GameEngine.pulseCost {
            charge = min(GameEngine.pulseCost, charge + cells)
            if charge == GameEngine.pulseCost { events.append(.coreCharged) }
        }

        if mode.levelsUp {
            let newLevel = ScoreCalculator.level(forTotalShards: shards,
                                                 startingAt: config.startLevel)
            if newLevel > level {
                level = newLevel
                events.append(.levelUp(level))
            }
        }

        if let target = mode.shardTarget, shards >= target {
            finish(.targetReached)
            return false
        }
        return true
    }

    private func finish(_ reason: GameOverReason) {
        if case .over = phase { return }
        // A Blitz clock can expire while cells are still playing their clear
        // animation. The points were awarded already, so the count follows.
        if !pendingClear.isEmpty {
            let cells = pendingClear
            pendingClear = []
            board.remove(Set(cells))
            shards += cells.count
            stats.shardsCleared += cells.count
        }
        phase = .over(reason)
        current = nil
        ghost = nil
        releaseAllInput()
        events.append(.gameOver(reason: reason))
    }

    /// Ring by ring from the rim, then clockwise, so event payloads are
    /// stable for tests and saved runs.
    private static func cellOrder(_ a: Point, _ b: Point) -> Bool {
        a.y == b.y ? a.x < b.x : a.y < b.y
    }
}
