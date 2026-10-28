import XCTest
@testable import iVidiBlocks

/// Deals every bag in the same order, so two engines stay in step however
/// many bags they draw.
private struct SameEveryBag: PieceRandomSource {
    func shuffle(_ shards: inout [Shard]) {
        shards = Shard.all
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

    private func playing(_ mode: GameMode = .orbit, seed: UInt64 = 7) -> GameEngine {
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
        let engine = GameEngine(mode: .orbit)
        XCTAssertNil(engine.snapshot())
        engine.pause()
        XCTAssertNil(engine.snapshot(), "pausing the countdown leaves nothing to resume")

        var blocked = Board()
        for y in 0..<Board.rings { blocked[0, y] = .tide }
        let over = GameEngine(mode: .orbit, board: blocked)
        over.startImmediately()
        XCTAssertNil(over.snapshot())
    }

    func testARestoredRunMatchesTheOriginalAndWaitsPaused() throws {
        let engine = playing()
        engine.move(dx: -1)
        engine.hardDrop()
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

        restored.resume()
        XCTAssertEqual(restored.phase, .playing)
    }

    func testARestoredRunPlaysOnIdenticallyToTheOriginal() throws {
        let engine = GameEngine(mode: .orbit, random: SameEveryBag())
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
        XCTAssertEqual(restored.charge, engine.charge)
    }

    func testARunSavedMidClearFinishesTheClearOnResume() throws {
        let lesson = try XCTUnwrap(Lesson.all.first { $0.goal == .chain(2) })
        let engine = GameEngine(mode: .target, random: LessonPieces(order: lesson.pieces),
                                board: lesson.board)
        engine.startImmediately()
        engine.hardDrop()
        XCTAssertEqual(engine.phase, .clearing)
        engine.pause()

        let saved = try XCTUnwrap(engine.snapshot())
        XCTAssertNil(saved.current)
        let restored = try XCTUnwrap(GameEngine(restoring: saved))
        restored.resume()
        XCTAssertEqual(restored.phase, .clearing)
        advance(restored, by: GameEngine.clearDuration + 0.05)
        XCTAssertEqual(restored.phase, .clearing, "the cascade's second link follows")
        XCTAssertEqual(restored.chain, 2)
        XCTAssertEqual(restored.shards, saved.shards + saved.pendingClear.count)
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
            for cell in piece.cells { broken.cells[cell.y * Board.sectors + cell.x] = .amber }
        }
        XCTAssertNil(GameEngine(restoring: broken), "a piece inside the stack")

        broken = saved
        broken.current = nil
        XCTAssertNil(GameEngine(restoring: broken), "no piece and nothing clearing")

        broken = saved
        broken.shards = 200
        XCTAssertNil(GameEngine(restoring: broken), "a level that does not follow the shards")

        broken = saved
        broken.mode = .target
        broken.shards = 160
        XCTAssertNil(GameEngine(restoring: broken), "a Target run that already reached its quota")

        broken = saved
        broken.mode = .blitz
        broken.elapsed = 120
        XCTAssertNil(GameEngine(restoring: broken), "a Blitz clock that already ran out")

        broken = saved
        broken.charge = GameEngine.pulseCost + 1
        XCTAssertNil(GameEngine(restoring: broken), "more charge than the core holds")

        broken = saved
        broken.aim = Board.sectors
        XCTAssertNil(GameEngine(restoring: broken), "an aim off the circle")

        broken = saved
        broken.elapsed = .nan
        XCTAssertNil(GameEngine(restoring: broken))

        broken = saved
        broken.pendingClear = [Point(x: 0, y: Board.rings - 1)]
        broken.chain = 1
        broken.current = nil
        XCTAssertNil(GameEngine(restoring: broken), "a clear of cells that would not clear")
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
