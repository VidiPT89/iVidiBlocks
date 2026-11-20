import XCTest
@testable import iVidiBlocks

private struct ClassicOrder: PieceRandomSource {
    var piece = Shard(shape: .o, color: .amber)
    func shuffle(_ shards: inout [Shard]) { shards = [piece] }
}
final class GameEngineTests: XCTestCase {
    func testWallsAndCentredSpawn() throws {
        let engine = GameEngine(mode: .orbit, random: ClassicOrder())
        engine.startImmediately()
        XCTAssertEqual(engine.current?.origin.x, 3)
        for _ in 0..<20 { engine.move(dx: -1) }
        XCTAssertEqual(engine.current?.cells.map(\.x).min(), 0)
        XCTAssertFalse(engine.move(dx: -1))
        engine.hardDrop()
        XCTAssertEqual(engine.current?.origin.x, 3)
        XCTAssertEqual(engine.stats.piecesPlaced, 1)
    }
    func testFourLineClearAndProgress() throws {
        let lesson = Lesson.all[2]
        let engine = GameEngine(mode: .orbit, random: LessonPieces(order: lesson.pieces), board: lesson.board)
        engine.startImmediately()
        XCTAssertTrue(engine.rotate(clockwise: true))
        engine.hardDrop()
        XCTAssertEqual(engine.phase, .clearing)
        XCTAssertEqual(engine.pendingClear.count, 40)
        XCTAssertGreaterThanOrEqual(engine.score, 1200)
        engine.update(deltaTime: GameEngine.clearDuration + 0.01)
        XCTAssertEqual(engine.shards, 4)
        XCTAssertEqual(engine.stats.ringsCleared, 4)
        XCTAssertTrue(engine.board.isEmpty())
        XCTAssertEqual(engine.phase, .playing)
    }
    func testBlockedSpawnEndsRun() {
        var board = Board()
        for y in 0..<4 { for x in 0..<10 { board[x,y] = .ember } }
        let engine = GameEngine(mode: .orbit, board: board)
        engine.startImmediately()
        XCTAssertEqual(engine.phase, .over(.topOut))
    }
    func testPauseFreezesAndRestoreKeepsQueue() throws {
        let engine = GameEngine(mode: .orbit)
        engine.startImmediately()
        engine.pause()
        let piece = engine.current
        engine.update(deltaTime: 10)
        XCTAssertEqual(engine.current, piece)
        let snapshot = try XCTUnwrap(engine.snapshot())
        let restored = try XCTUnwrap(GameEngine(restoring: snapshot))
        XCTAssertEqual(restored.current, piece)
        XCTAssertEqual(restored.preview, engine.preview)
        restored.resume()
        XCTAssertEqual(restored.phase, .playing)
    }
    func testClockExpiresAndPulseIsUnavailable() {
        let engine = GameEngine(mode: .blitz, charge: GameEngine.pulseCost)
        engine.startImmediately()
        XCTAssertFalse(engine.canPulse)
        engine.update(deltaTime: 0.01, clockDeltaTime: 121)
        XCTAssertEqual(engine.phase, .over(.timeUp))
    }
    func testGravityAndSoftDrop() throws {
        let engine = GameEngine(mode: .orbit)
        engine.startImmediately()
        let y = try XCTUnwrap(engine.current).origin.y
        engine.update(deltaTime: ScoreCalculator.gravityInterval(level: 1))
        XCTAssertEqual(engine.current?.origin.y, y + 1)
        engine.softDropStep()
        XCTAssertEqual(engine.current?.origin.y, y + 2)
        XCTAssertEqual(engine.score, 1)
    }
    func testTargetFinishesAtFortyLines() throws {
        let lesson = Lesson.all[0]
        let engine = GameEngine(mode: .target, random: LessonPieces(order: lesson.pieces), board: lesson.board)
        engine.startImmediately()
        engine.hardDrop()
        var saved = try XCTUnwrap(engine.snapshot())
        saved.shards = 38
        let restored = try XCTUnwrap(GameEngine(restoring: saved))
        restored.resume()
        restored.update(deltaTime: GameEngine.clearDuration + 0.01)
        XCTAssertEqual(restored.shards, 40)
        XCTAssertEqual(restored.phase, .over(.targetReached))
    }
    func testSaveAtLeftWallRestores() throws {
        let engine = GameEngine(mode: .orbit, random: ClassicOrder())
        engine.startImmediately()
        for _ in 0..<10 { engine.move(dx: -1) }
        XCTAssertNotNil(GameEngine(restoring: try XCTUnwrap(engine.snapshot())))
    }

}
