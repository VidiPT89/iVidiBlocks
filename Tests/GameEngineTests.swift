import XCTest
@testable import iTetris

/// Hands out the seven pieces in a fixed order so a test can rely on
/// exactly which piece is falling.
private struct FixedBagOrder: PieceRandomSource {
    let order: [TetrominoType]
    func shuffle(_ pieces: inout [TetrominoType]) { pieces = order }
}

final class GameEngineTests: XCTestCase {

    private let ordered = FixedBagOrder(order: [.i, .o, .t, .s, .z, .j, .l])

    private func engine(mode: GameMode = .marathon,
                        board: Board = Board(),
                        config: GameConfig = .default) -> GameEngine {
        let engine = GameEngine(mode: mode, config: config, random: ordered, board: board)
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

    private func filledRow(except gaps: [Int], at y: Int, on board: inout Board) {
        for x in 0..<Board.columns where !gaps.contains(x) {
            board[x, y] = .z
        }
    }

    // MARK: Spawning

    func testStartSpawnsTheFirstPieceOfTheBag() {
        let engine = engine()
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.current?.type, .i)
        XCTAssertEqual(engine.preview.count, RandomBag.previewCount)
    }

    func testCountdownRunsBeforeTheFirstPieceAppears() {
        let engine = GameEngine(mode: .marathon, random: ordered)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertNil(engine.current)

        advance(engine, by: GameEngine.readyDuration + 0.1)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertNotNil(engine.current)
    }

    func testGameEndsImmediatelyWhenTheSpawnAreaIsBlocked() {
        var board = Board()
        for y in 0..<4 { filledRow(except: [], at: y, on: &board) }
        let engine = engine(board: board)
        XCTAssertEqual(engine.phase, .over(.topOut))
    }

    // MARK: Movement

    func testMovingStopsAtTheWalls() {
        let engine = engine()
        while engine.move(dx: -1) {}
        XCTAssertEqual(engine.current?.cells.map(\.x).min(), 0)

        while engine.move(dx: 1) {}
        XCTAssertEqual(engine.current?.cells.map(\.x).max(), Board.columns - 1)
    }

    func testGravityDropsThePieceOneRowPerInterval() {
        let engine = engine()
        let startY = engine.current!.origin.y
        advance(engine, by: ScoreCalculator.gravityInterval(level: 1) + 0.02)
        XCTAssertEqual(engine.current?.origin.y, startY + 1)
    }

    func testGhostSitsWhereAHardDropWouldLand() {
        let engine = engine()
        let ghost = engine.ghost
        XCTAssertNotNil(ghost)
        XCTAssertEqual(ghost?.cells.map(\.y).max(), Board.rows - 1)
        XCTAssertEqual(ghost?.origin.x, engine.current?.origin.x)
    }

    func testGhostIsAbsentWhenTurnedOff() {
        var config = GameConfig.default
        config.ghostEnabled = false
        let engine = engine(config: config)
        XCTAssertNil(engine.ghost)
    }

    // MARK: Dropping and locking

    func testHardDropLocksAndBringsInTheNextPiece() {
        let engine = engine()
        engine.hardDrop()
        XCTAssertEqual(engine.current?.type, .o, "the next piece should be up")
        XCTAssertEqual(engine.stats.piecesPlaced, 1)
        XCTAssertGreaterThan(engine.score, 0, "a hard drop pays two points per row")
    }

    func testAPieceOnTheFloorDoesNotLockBeforeTheDelayExpires() {
        let engine = engine()
        engine.setHorizontalInput(0)
        let landed = engine.board.hardDropPosition(of: engine.current!)
        while engine.current!.origin.y < landed.origin.y {
            advance(engine, by: ScoreCalculator.gravityInterval(level: 1) + 0.001)
        }

        advance(engine, by: GameEngine.lockDelay * 0.5)
        XCTAssertEqual(engine.stats.piecesPlaced, 0, "it locked too early")

        advance(engine, by: GameEngine.lockDelay)
        XCTAssertEqual(engine.stats.piecesPlaced, 1, "it never locked")
    }

    func testMovingOnTheFloorCannotStallForever() {
        let engine = engine()
        engine.hardDrop()                      // place the I flat on the floor
        let resting = engine.current!
        _ = resting

        // Bring the next piece down to the floor, then wiggle it endlessly.
        while engine.board.canPlace(engine.current!.moved(dx: 0, dy: 1)) {
            advance(engine, by: ScoreCalculator.gravityInterval(level: 1) + 0.001)
        }
        for step in 0..<200 {
            engine.move(dx: step.isMultiple(of: 2) ? -1 : 1)
            advance(engine, by: 0.05)
            if engine.stats.piecesPlaced > 1 { break }
        }
        XCTAssertGreaterThan(engine.stats.piecesPlaced, 1,
                             "the move-reset limit should force the lock")
    }

    // MARK: Hold

    func testHoldStoresThePieceAndCanOnlyBeUsedOncePerPiece() {
        let engine = engine()
        XCTAssertEqual(engine.current?.type, .i)

        engine.hold()
        XCTAssertEqual(engine.holdPiece, .i)
        XCTAssertEqual(engine.current?.type, .o, "the next piece takes over")

        engine.hold()
        XCTAssertEqual(engine.holdPiece, .i, "a second hold must be refused")
        XCTAssertEqual(engine.current?.type, .o)
        XCTAssertTrue(engine.drainEvents().contains(.holdRejected))
    }

    func testHoldSwapsBackAfterAPieceLocks() {
        let engine = engine()
        engine.hold()                       // I into hold, O now falling
        engine.hardDrop()                   // lock the O, hold frees up
        XCTAssertEqual(engine.current?.type, .t)

        engine.hold()
        XCTAssertEqual(engine.holdPiece, .t)
        XCTAssertEqual(engine.current?.type, .i, "the stored I should come back")
        XCTAssertEqual(engine.current?.state, .spawn, "and re-enter unrotated")
    }

    // MARK: Line clears

    func testCompletingARowClearsItAfterTheAnimationDelay() {
        var board = Board()
        filledRow(except: [0, 1, 2, 3], at: Board.rows - 1, on: &board)
        let engine = engine(board: board)

        while engine.move(dx: -1) {}
        engine.hardDrop()

        XCTAssertEqual(engine.phase, .clearing)
        XCTAssertEqual(engine.pendingClearRows, [Board.rows - 1])
        XCTAssertEqual(engine.lines, 0, "the count waits for the animation")

        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.lines, 1)
        XCTAssertTrue(engine.board.isEmpty(), "that was also a perfect clear")
    }

    func testAPerfectClearScoresItsBonus() {
        var board = Board()
        filledRow(except: [0, 1, 2, 3], at: Board.rows - 1, on: &board)
        let engine = engine(board: board)
        while engine.move(dx: -1) {}
        engine.hardDrop()

        let cleared = engine.drainEvents().compactMap { event -> ClearOutcome? in
            if case let .linesCleared(_, outcome) = event { return outcome }
            return nil
        }.first

        XCTAssertEqual(cleared?.lines, 1)
        XCTAssertEqual(cleared?.perfectClear, true)
        XCTAssertEqual(cleared?.points, 800, "a perfect single is worth 800 at level 1")
    }

    func testComboResetsWhenAPieceClearsNothing() {
        var board = Board()
        filledRow(except: [0, 1, 2, 3], at: Board.rows - 1, on: &board)
        filledRow(except: [0, 1, 2, 3], at: Board.rows - 2, on: &board)
        let engine = engine(board: board)

        while engine.move(dx: -1) {}
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.combo, 0, "first clear of a chain")

        while engine.move(dx: -1) {}
        engine.hardDrop()                    // the O drops into the open left
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.combo, -1, "a clear-less piece breaks the chain")
    }

    // MARK: Modes

    func testUltraCountsDownFromThreeMinutes() throws {
        let engine = engine(mode: .ultra)
        XCTAssertEqual(try XCTUnwrap(engine.timeRemaining), 180, accuracy: 0.1)

        advance(engine, by: 5)
        XCTAssertEqual(try XCTUnwrap(engine.timeRemaining), 175, accuracy: 0.2)
    }

    func testUltraEndsWhenTheClockRunsOut() {
        let engine = engine(mode: .ultra)
        // One long step so the clock expires before gravity gets a turn,
        // which is the branch under test. Left to run in real time the
        // stack would top out first, and that is a different ending.
        engine.update(deltaTime: 181)
        XCTAssertEqual(engine.phase, .over(.timeUp))
        XCTAssertEqual(engine.timeRemaining, 0)
    }

    func testAnUnplayedUltraRunStillTopsOut() {
        let engine = engine(mode: .ultra)
        advance(engine, by: 181)
        XCTAssertEqual(engine.phase, .over(.topOut))
    }

    func testSprintTracksTheLinesLeft() {
        var board = Board()
        filledRow(except: [0, 1, 2, 3], at: Board.rows - 1, on: &board)
        let engine = engine(mode: .sprint, board: board)
        XCTAssertEqual(engine.linesRemaining, 40)

        while engine.move(dx: -1) {}
        engine.hardDrop()
        advance(engine, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(engine.linesRemaining, 39)
    }

    func testMarathonIsTheOnlyModeThatGainsLevels() {
        XCTAssertTrue(GameMode.marathon.levelsUp)
        XCTAssertFalse(GameMode.sprint.levelsUp)
        XCTAssertFalse(GameMode.ultra.levelsUp)
        XCTAssertEqual(GameMode.sprint.lineTarget, 40)
        XCTAssertEqual(GameMode.ultra.timeLimit, 180)
        XCTAssertNil(GameMode.marathon.lineTarget)
        XCTAssertNil(GameMode.marathon.timeLimit)
    }

    // MARK: Pausing

    func testPausingFreezesGravity() {
        let engine = engine()
        let y = engine.current!.origin.y
        engine.pause()
        advance(engine, by: 5)
        XCTAssertEqual(engine.current?.origin.y, y)

        engine.resume()
        advance(engine, by: ScoreCalculator.gravityInterval(level: 1) + 0.02)
        XCTAssertEqual(engine.current?.origin.y, y + 1)
    }

    func testInputIsIgnoredOnceTheGameIsOver() {
        var board = Board()
        for y in 0..<4 { filledRow(except: [], at: y, on: &board) }
        let engine = engine(board: board)

        XCTAssertFalse(engine.move(dx: -1))
        XCTAssertFalse(engine.rotate(clockwise: true))
        engine.hardDrop()
        XCTAssertEqual(engine.phase, .over(.topOut))
    }
}
