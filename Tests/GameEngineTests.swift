import XCTest
@testable import iVidiBlocks

/// Hands out shards in a fixed order so a test can rely on exactly which
/// shard is falling.
private struct FixedBagOrder: PieceRandomSource {
    let order: [Shard]
    func shuffle(_ shards: inout [Shard]) { shards = order }
}

final class GameEngineTests: XCTestCase {

    private let core = Board.rings - 1
    private let duo = Shard(shape: .duo, color: .amber)
    private let spark = Shard(shape: .spark, color: .ember)

    private func engine(mode: GameMode = .orbit,
                        board: Board = Board(),
                        order: [Shard]? = nil,
                        config: GameConfig = .default,
                        charge: Int = 0) -> GameEngine {
        let engine = GameEngine(mode: mode, config: config,
                                random: FixedBagOrder(order: order ?? [duo]),
                                board: board, charge: charge)
        engine.startImmediately()
        return engine
    }

    /// Steps the clock in small slices so gravity and lock delay both tick.
    private func advance(_ engine: GameEngine, by seconds: TimeInterval) {
        let step = 1.0 / 60.0
        var remaining = seconds
        while remaining > 0 {
            engine.update(deltaTime: min(step, remaining))
            remaining -= step
        }
    }

    /// Fills a ring with alternating colours, leaving the given sectors open.
    private func ring(at y: Int, except gaps: [Int], on board: inout Board) {
        let colors: [ShardColor] = [.tide, .ember]
        for x in 0..<Board.sectors where !gaps.contains(x) {
            board[x, y] = colors[x % 2]
        }
    }

    // MARK: Spawning and moving

    func testStartSpawnsTheFirstShardJustInsideTheRim() throws {
        let engine = engine()
        let piece = try XCTUnwrap(engine.current)
        XCTAssertEqual(piece.shard, duo)
        XCTAssertEqual(piece.origin, Point(x: 0, y: Board.bufferRings))
    }

    func testCountdownRunsBeforeTheFirstShardAppears() {
        let engine = GameEngine(mode: .orbit)
        XCTAssertNil(engine.current)
        engine.update(deltaTime: GameEngine.readyDuration / 2)
        XCTAssertNil(engine.current)
        engine.update(deltaTime: GameEngine.readyDuration)
        XCTAssertNotNil(engine.current)
    }

    func testMovingWrapsAllTheWayRoundWithoutWalls() throws {
        let engine = engine()
        XCTAssertTrue(engine.move(dx: -1))
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.x, Board.sectors - 1)
        for _ in 0..<Board.sectors { XCTAssertTrue(engine.move(dx: 1)) }
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.x, Board.sectors - 1)
    }

    func testMovingIsBlockedOnlyByCells() {
        var board = Board()
        board[2, Board.bufferRings] = .tide
        let engine = engine(board: board)
        XCTAssertFalse(engine.move(dx: 1))
    }

    func testTheNextShardEntersWhereTheLastOneLanded() throws {
        let engine = engine()
        for _ in 0..<5 { engine.move(dx: 1) }
        engine.hardDrop()
        XCTAssertEqual(engine.aim, 5)
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.x, 5)
    }

    func testGravityPullsTheShardOneRingPerInterval() throws {
        let engine = engine()
        let start = try XCTUnwrap(engine.current).origin.y
        advance(engine, by: ScoreCalculator.gravityInterval(level: 1) + 0.01)
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.y, start + 1)
    }

    func testGhostSitsWhereADropWouldLand() throws {
        let engine = engine()
        XCTAssertEqual(try XCTUnwrap(engine.ghost).origin.y, core)
        let off = self.engine(config: GameConfig(ghostEnabled: false))
        XCTAssertNil(off.ghost)
    }

    func testDroppingLocksAgainstTheCoreAndDealsTheNextShard() {
        let engine = engine()
        engine.hardDrop()
        XCTAssertEqual(engine.board[0, core], .amber)
        XCTAssertEqual(engine.board[1, core], .amber)
        XCTAssertEqual(engine.stats.piecesPlaced, 1)
        XCTAssertNotNil(engine.current)
        XCTAssertGreaterThan(engine.score, 0, "a drop earns a little")
    }

    func testALandedShardWaitsForTheLockDelay() throws {
        let engine = engine()
        while engine.current.map({ $0.origin.y }) != core {
            advance(engine, by: ScoreCalculator.gravityInterval(level: 1))
        }
        advance(engine, by: GameEngine.lockDelay / 2)
        XCTAssertEqual(engine.stats.piecesPlaced, 0)
        advance(engine, by: GameEngine.lockDelay)
        XCTAssertEqual(engine.stats.piecesPlaced, 1)
    }

    func testMovingOnTheCoreCannotStallForever() {
        let engine = engine()
        engine.setSoftDrop(true)
        advance(engine, by: 1)
        engine.setSoftDrop(false)
        for step in 0..<200 {
            engine.move(dx: step % 2 == 0 ? 1 : -1)
            advance(engine, by: 0.1)
            if engine.stats.piecesPlaced > 0 { break }
        }
        XCTAssertEqual(engine.stats.piecesPlaced, 1)
    }

    func testABlockedEntryEndsTheRun() {
        var board = Board()
        for y in 0..<Board.rings { board[0, y] = .tide }
        let engine = engine(board: board)
        XCTAssertEqual(engine.phase, .over(.topOut))
        XCTAssertNil(engine.snapshot())
    }

    // MARK: Clearing

    func testClosingARingClearsItAfterTheAnimation() {
        var board = Board()
        ring(at: core, except: [0, 1], on: &board)
        let engine = engine(board: board)
        engine.hardDrop()
        XCTAssertEqual(engine.phase, .clearing)
        XCTAssertEqual(engine.pendingClear.count, Board.sectors)
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains { if case let .cleared(_, _, outcome) = $0 { return outcome.rings == 1 }; return false })

        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertTrue(engine.board.isEmpty())
        XCTAssertEqual(engine.shards, Board.sectors)
        XCTAssertEqual(engine.stats.ringsCleared, 1)
    }

    func testFusingAnArcClearsOnlyThoseCells() {
        var board = Board()
        for x in 2...4 { board[x, core] = .amber }
        board[5, core] = .tide
        let engine = engine(board: board)
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.stats.arcsFused, 1)
        XCTAssertEqual(engine.board.cells.compactMap { $0 }, [.tide])
    }

    func testCellsSlidingInwardsCanSetOffAChain() throws {
        let lesson = try XCTUnwrap(Lesson.all.first { $0.goal == .chain(2) })
        let engine = engine(board: lesson.board)
        engine.hardDrop()
        var chains: [Int] = []
        for _ in 0..<60 {
            for case let .cleared(_, _, outcome) in engine.drainEvents() { chains.append(outcome.chain) }
            advance(engine, by: 1.0 / 30.0)
        }
        XCTAssertEqual(chains, [1, 2])
        XCTAssertEqual(engine.stats.maxChain, 2)
        XCTAssertEqual(engine.chain, 0, "the cascade is over")
    }

    func testAChainLinkMultipliesItsStep() throws {
        let lesson = try XCTUnwrap(Lesson.all.first { $0.goal == .chain(2) })
        let engine = engine(board: lesson.board)
        engine.hardDrop()
        var outcomes: [ClearOutcome] = []
        for _ in 0..<60 {
            for case let .cleared(_, _, outcome) in engine.drainEvents() { outcomes.append(outcome) }
            advance(engine, by: 1.0 / 30.0)
        }
        let second = try XCTUnwrap(outcomes.last)
        XCTAssertEqual(second.chain, 2)
        XCTAssertEqual(second.points, ScoreCalculator.points(cells: second.cells, rings: 0,
                                                            arcs: 1, chain: 1, level: 1) * 2)
    }

    // MARK: Core pulse

    func testClearedCellsChargeTheCore() {
        var board = Board()
        ring(at: core, except: [0, 1], on: &board)
        let engine = engine(board: board)
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.charge, Board.sectors)
        XCTAssertFalse(engine.canPulse)
    }

    func testAFullChargeIsAnnouncedOnce() {
        var board = Board()
        ring(at: core, except: [0, 1], on: &board)
        let engine = engine(board: board, charge: GameEngine.pulseCost - 4)
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        let charged = engine.drainEvents().filter { $0 == .coreCharged }
        XCTAssertEqual(charged.count, 1)
        XCTAssertEqual(engine.charge, GameEngine.pulseCost)
        XCTAssertTrue(engine.canPulse)
    }

    func testAPulseWipesTheTwoInnermostRingsAndSpendsTheCharge() {
        var board = Board()
        ring(at: core, except: [3], on: &board)
        ring(at: core - 1, except: [3, 4], on: &board)
        board[7, core - 2] = .amber
        let engine = engine(board: board, order: [spark], charge: GameEngine.pulseCost)
        engine.pulse()
        XCTAssertEqual(engine.charge, 0)
        XCTAssertEqual(engine.board.cells.compactMap { $0 }, [.amber])
        XCTAssertEqual(engine.board[7, core], .amber, "outer cells slide all the way in")
        XCTAssertEqual(engine.stats.pulses, 1)
        XCTAssertTrue(engine.drainEvents().contains { if case .pulsed = $0 { return true }; return false })
    }

    func testAPulseWithoutChargeIsRefused() {
        var board = Board()
        board[5, core] = .tide
        let engine = engine(board: board)
        engine.pulse()
        XCTAssertEqual(engine.board[5, core], .tide)
        XCTAssertEqual(engine.drainEvents().last, .pulseRejected)
    }

    // MARK: Modes

    func testTargetEndsOnceItsQuotaIsCleared() throws {
        var board = Board()
        ring(at: core, except: [0, 1], on: &board)
        let fresh = engine(mode: .target, board: board)
        XCTAssertEqual(fresh.shardsRemaining, 160)
        var saved = try XCTUnwrap(fresh.snapshot())
        saved.shards = 150
        let engine = try XCTUnwrap(GameEngine(restoring: saved, random: FixedBagOrder(order: [duo])))
        engine.resume()
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.phase, .over(.targetReached))
        XCTAssertEqual(engine.shardsRemaining, 0)
    }

    func testBlitzCountsDownAndEndsOnTime() throws {
        let engine = engine(mode: .blitz)
        XCTAssertEqual(try XCTUnwrap(engine.timeRemaining), 120)
        engine.update(deltaTime: 1.0 / 60.0, clockDeltaTime: 120)
        XCTAssertEqual(engine.phase, .over(.timeUp))
        XCTAssertEqual(engine.elapsed, 120)
    }

    func testOnlyOrbitGainsLevels() {
        for mode in GameMode.allCases {
            var board = Board()
            for y in (core - 3)...core { ring(at: y, except: [0], on: &board) }
            let engine = engine(mode: mode, board: board,
                                order: [Shard(shape: .trio, color: .amber)])
            engine.rotate(clockwise: true)
            engine.hardDrop()
            advance(engine, by: GameEngine.clearDuration + 0.05)
            engine.hardDrop()
            advance(engine, by: 0.5)
            XCTAssertEqual(engine.level > 1, mode == .orbit, "\(mode)")
        }
    }

    // MARK: Pausing, danger and input hygiene

    func testPausingFreezesGravityAndTheClock() throws {
        let engine = engine()
        let y = try XCTUnwrap(engine.current).origin.y
        engine.pause()
        advance(engine, by: 3)
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.y, y)
        XCTAssertEqual(engine.elapsed, 0)
        engine.resume()
        XCTAssertEqual(engine.phase, .playing)
    }

    func testDangerRisesAsTheStackNearsTheRim() {
        XCTAssertEqual(engine().dangerLevel, 0)
        var board = Board()
        board[8, Board.bufferRings] = .tide
        let engine = engine(board: board)
        XCTAssertEqual(engine.dangerLevel, 1)
    }

    func testInputIsIgnoredOnceTheGameIsOver() {
        let engine = engine(mode: .blitz)
        engine.update(deltaTime: 1.0 / 60.0, clockDeltaTime: 200)
        XCTAssertFalse(engine.move(dx: 1))
        XCTAssertFalse(engine.rotate(clockwise: true))
        engine.hardDrop()
        engine.pulse()
        XCTAssertEqual(engine.stats.piecesPlaced, 0)
    }

    func testInvalidFrameDurationsDoNotChangeTheRun() {
        let engine = engine()
        let before = engine.current
        engine.update(deltaTime: .nan)
        engine.update(deltaTime: -1)
        engine.update(deltaTime: .infinity)
        XCTAssertEqual(engine.current, before)
        XCTAssertEqual(engine.elapsed, 0)
    }

    func testHeldSidewaysInputRepeatsAndStopsOnRelease() throws {
        let engine = engine()
        engine.setHorizontalInput(1)
        advance(engine, by: 0.4)
        let moved = try XCTUnwrap(engine.current).origin.x
        XCTAssertGreaterThan(moved, 2)
        engine.setHorizontalInput(0)
        advance(engine, by: 0.3)
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.x, moved)
    }

    func testAnInstantRepeatStopsAfterOneLap() {
        let engine = engine(config: GameConfig(das: 0, arr: 0))
        engine.setHorizontalInput(1)
        engine.update(deltaTime: 1.0 / 60.0)
        XCTAssertLessThanOrEqual(engine.drainEvents().filter { $0 == .moved }.count, Board.sectors + 1)
    }

    func testAccessibleSoftDropMovesOneRingAndScoresOnePoint() throws {
        let engine = engine()
        let y = try XCTUnwrap(engine.current).origin.y
        engine.softDropStep()
        XCTAssertEqual(try XCTUnwrap(engine.current).origin.y, y + 1)
        XCTAssertEqual(engine.score, 1)
    }

    func testDropEventDescribesTheShardThatLanded() throws {
        let engine = engine()
        _ = engine.drainEvents()
        engine.hardDrop()
        let drop = engine.drainEvents().first { if case .hardDropped = $0 { return true }; return false }
        guard case let .hardDropped(rings, from, piece) = try XCTUnwrap(drop) else { return XCTFail() }
        XCTAssertEqual(from, Board.bufferRings)
        XCTAssertEqual(rings, core - Board.bufferRings)
        XCTAssertEqual(piece.origin.y, core)
    }

    /// Plays many seeded runs with mixed input and checks that nothing the
    /// renderer depends on is ever broken.
    func testSeededMixedInputPreservesInvariants() {
        for mode in GameMode.allCases {
            for seed in 1...15 {
                let engine = GameEngine(mode: mode, random: SeededPieceRandom(seed: UInt64(seed)))
                engine.startImmediately()
                var lastScore = 0
                var lastShards = 0
                for step in 0..<400 {
                    switch (step * 7 + seed) % 6 {
                    case 0: engine.move(dx: 1)
                    case 1: engine.move(dx: -1)
                    case 2: engine.rotate(clockwise: step % 2 == 0)
                    case 3: engine.hardDrop()
                    case 4: engine.pulse()
                    default: engine.softDropStep()
                    }
                    advance(engine, by: 0.05)
                    if let piece = engine.current {
                        XCTAssertTrue(engine.board.canPlace(piece))
                        if let ghost = engine.ghost {
                            XCTAssertEqual(engine.board.dropPosition(of: piece), ghost)
                        }
                    }
                    XCTAssertEqual(engine.board.cells.count, Board.sectors * Board.rings)
                    XCTAssertGreaterThanOrEqual(engine.score, lastScore)
                    XCTAssertGreaterThanOrEqual(engine.shards, lastShards)
                    XCTAssertTrue((0...GameEngine.pulseCost).contains(engine.charge))
                    lastScore = engine.score
                    lastShards = engine.shards
                    if case .over = engine.phase { break }
                }
            }
        }
    }
}
