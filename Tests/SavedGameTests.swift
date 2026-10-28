import XCTest
@testable import iTetris

/// Deals every bag in the same order, so two engines stay in step however
/// many bags they draw.
private struct SameEveryBag: PieceRandomSource {
    func shuffle(_ pieces: inout [TetrominoType]) {
        pieces = [.i, .o, .t, .s, .z, .j, .l]
    }
}

/// A run saved on the way out has to come back exactly as it was, and a
/// file that could not have come from a real game must never reach the
/// engine.
final class SavedGameTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func playing(_ mode: GameMode = .marathon, seed: UInt64 = 7) -> GameEngine {
        let engine = GameEngine(mode: mode, random: SeededPieceRandom(seed: seed))
        engine.startImmediately()
        return engine
    }

    private func advance(_ engine: GameEngine, by seconds: TimeInterval) {
        var remaining = seconds
        while remaining > 0 {
            engine.update(deltaTime: min(1.0 / 60.0, remaining))
            remaining -= 1.0 / 60.0
        }
    }

    // MARK: Engine

    func testNothingIsSavedBeforeTheFirstPieceOrAfterTheEnd() {
        let engine = GameEngine(mode: .marathon)
        XCTAssertNil(engine.snapshot())
        engine.pause()
        XCTAssertNil(engine.snapshot(), "pausing the countdown leaves nothing to resume")

        var blocked = Board()
        for y in 0..<4 { for x in 0..<Board.columns { blocked[x, y] = .z } }
        let over = GameEngine(mode: .marathon, board: blocked)
        over.startImmediately()
        XCTAssertNil(over.snapshot())
    }

    func testARestoredRunMatchesTheOriginalAndWaitsPaused() throws {
        let engine = playing()
        engine.move(dx: -1)
        engine.hardDrop()
        engine.hold()
        engine.rotate(clockwise: true)
        advance(engine, by: 0.3)
        engine.pause()

        let saved = try XCTUnwrap(engine.snapshot())
        let restored = try XCTUnwrap(GameEngine(restoring: saved))
        XCTAssertEqual(restored.phase, .paused)
        var again = try XCTUnwrap(restored.snapshot())
        // The bag tops itself up on restore, as the original would on its
        // next draw; what was already dealt still comes first.
        XCTAssertEqual(Array(again.queue.prefix(saved.queue.count)), saved.queue)
        again.queue = saved.queue
        XCTAssertEqual(again, saved)
        XCTAssertEqual(restored.preview, engine.preview)
        XCTAssertEqual(restored.ghost, engine.ghost)
        XCTAssertFalse(restored.canHold, "hold was already spent on this piece")

        restored.resume()
        XCTAssertEqual(restored.phase, .playing)
    }

    func testARestoredRunPlaysOnIdenticallyToTheOriginal() throws {
        let engine = GameEngine(mode: .marathon, random: SameEveryBag())
        engine.startImmediately()
        for _ in 0..<5 { engine.hardDrop() }
        let saved = try XCTUnwrap(engine.snapshot())
        let restored = try XCTUnwrap(GameEngine(restoring: saved, random: SameEveryBag()))
        restored.resume()

        for engine in [engine, restored] {
            for step in 0..<12 {
                engine.move(dx: step % 3 - 1)
                engine.rotate(clockwise: step % 2 == 0)
                engine.hardDrop()
            }
        }
        XCTAssertEqual(restored.board.cells, engine.board.cells)
        XCTAssertEqual(restored.score, engine.score)
        XCTAssertEqual(restored.current, engine.current)
        XCTAssertEqual(restored.holdPiece, engine.holdPiece)
    }

    func testARunSavedMidClearFinishesTheClearOnResume() throws {
        var board = Board()
        for x in 0..<(Board.columns - 1) { board[x, Board.rows - 1] = .z }
        let engine = GameEngine(mode: .sprint, random: SameEveryBag(), board: board)
        engine.startImmediately()
        // Stand the I piece upright in the gap on the right wall.
        engine.rotate(clockwise: true)
        while engine.move(dx: 1) {}
        engine.hardDrop()
        XCTAssertEqual(engine.phase, .clearing)
        engine.pause()

        let saved = try XCTUnwrap(engine.snapshot())
        XCTAssertNil(saved.current)
        let restored = try XCTUnwrap(GameEngine(restoring: saved))
        restored.resume()
        XCTAssertEqual(restored.phase, .clearing)
        advance(restored, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(restored.phase, .playing)
        XCTAssertEqual(restored.lines, saved.lines + saved.pendingClearRows.count)
    }

    func testImpossibleSnapshotsAreRefused() throws {
        let saved = try XCTUnwrap(playing().snapshot())
        XCTAssertNotNil(GameEngine(restoring: saved))

        var broken = saved
        broken.version = GameSnapshot.currentVersion + 1
        XCTAssertNil(GameEngine(restoring: broken), "another version's file")

        broken = saved
        broken.cells.removeLast()
        XCTAssertNil(GameEngine(restoring: broken), "a board of the wrong size")

        broken = saved
        if let piece = saved.current {
            for cell in piece.cells { broken.cells[cell.y * Board.columns + cell.x] = .o }
        }
        XCTAssertNil(GameEngine(restoring: broken), "a piece inside the stack")

        broken = saved
        broken.current = nil
        XCTAssertNil(GameEngine(restoring: broken), "no piece and nothing clearing")

        broken = saved
        broken.lines = 30
        XCTAssertNil(GameEngine(restoring: broken), "a level that does not follow the lines")

        broken = saved
        broken.mode = .sprint
        broken.lines = 40
        XCTAssertNil(GameEngine(restoring: broken), "a Sprint that already reached its target")

        broken = saved
        broken.mode = .ultra
        broken.elapsed = 180
        XCTAssertNil(GameEngine(restoring: broken), "an Ultra clock that already ran out")

        broken = saved
        broken.elapsed = .nan
        XCTAssertNil(GameEngine(restoring: broken))

        broken = saved
        broken.pendingClearRows = [Board.rows - 1]
        broken.current = nil
        XCTAssertNil(GameEngine(restoring: broken), "a clear of a row that is not full")
    }

    func testCurrentSettingsApplyButTheStartLevelIsKept() throws {
        var saved = try XCTUnwrap(playing().snapshot())
        saved.startLevel = 3
        saved.level = 3
        let config = GameConfig(das: 0.2, arr: 0.05, ghostEnabled: false, startLevel: 1)
        let restored = try XCTUnwrap(GameEngine(restoring: saved, config: config))
        XCTAssertEqual(restored.config.startLevel, 3)
        XCTAssertEqual(restored.config.das, 0.2)
        XCTAssertNil(restored.ghost, "the ghost follows the current setting")
    }

    // MARK: Store

    func testTheStoreKeepsARunAcrossLaunches() throws {
        let saved = try XCTUnwrap(playing().snapshot())
        SavedGameStore(fileURL: fileURL).save(saved)
        XCTAssertEqual(SavedGameStore(fileURL: fileURL).snapshot, saved)
    }

    func testClearingRemovesTheFile() throws {
        let store = SavedGameStore(fileURL: fileURL)
        store.save(try XCTUnwrap(playing().snapshot()))
        store.clear()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(SavedGameStore(fileURL: fileURL).snapshot)
    }

    func testAnUnreadableOrImpossibleFileIsDiscarded() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertNil(SavedGameStore(fileURL: fileURL).snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        var impossible = try XCTUnwrap(playing().snapshot())
        impossible.cells = []
        try JSONEncoder().encode(impossible).write(to: fileURL)
        XCTAssertNil(SavedGameStore(fileURL: fileURL).snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
