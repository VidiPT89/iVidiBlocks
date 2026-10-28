import XCTest
@testable import iVidiBlocks

/// Every drill has to be winnable with the pieces it deals, by the moves its
/// hint describes, and has to end once those pieces are spent.
final class LessonTests: XCTestCase {

    private func lesson(_ id: String) throws -> Lesson {
        try XCTUnwrap(Lesson.all.first { $0.id == id })
    }

    private func start(_ lesson: Lesson) -> GameEngine {
        let engine = GameEngine(mode: .marathon,
                                random: LessonPieces(order: lesson.pieces),
                                board: lesson.board)
        engine.startImmediately()
        return engine
    }

    /// Runs the clock in frame-sized steps, feeding every event to the tracker.
    private func advance(_ engine: GameEngine, _ tracker: inout LessonTracker, by seconds: Double) {
        var remaining = seconds
        repeat {
            engine.update(deltaTime: min(1.0 / 60.0, max(remaining, 0.001)))
            feed(engine, &tracker)
            remaining -= 1.0 / 60.0
        } while remaining > 0
    }

    private func feed(_ engine: GameEngine, _ tracker: inout LessonTracker) {
        for event in engine.drainEvents() { tracker.observe(event) }
        tracker.settle()
    }

    private func slide(_ engine: GameEngine, _ direction: Int) {
        while engine.move(dx: direction) {}
    }

    // MARK: Solvable

    func testEveryLessonHasAFullTenColumnBoardAndPieces() {
        XCTAssertEqual(Set(Lesson.all.map(\.id)).count, Lesson.all.count)
        for lesson in Lesson.all {
            XCTAssertFalse(lesson.pieces.isEmpty, lesson.id)
            XCTAssertTrue(lesson.rows.allSatisfy { $0.count == Board.columns }, lesson.id)
            XCTAssertTrue(lesson.board.completedRows().isEmpty, "\(lesson.id) starts with a full row")
        }
        XCTAssertNil(Lesson.all.last?.next)
        XCTAssertEqual(Lesson.all.first?.next, Lesson.all[1])
    }

    func testHardDropLesson() throws {
        let lesson = try lesson("drop")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testRotateLesson() throws {
        let lesson = try lesson("rotate")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.rotate(clockwise: true)
        slide(engine, 1)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testHoldLessonPassesOnlyWithHold() throws {
        let lesson = try lesson("hold")
        var engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hold()
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)

        engine = start(lesson)
        tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .inProgress)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .failed, "both pieces spent without holding")
    }

    func testQuadLesson() throws {
        let lesson = try lesson("quad")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.rotate(clockwise: true)
        slide(engine, -1)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testTSpinLessonNeedsTheSpin() throws {
        let lesson = try lesson("tspin")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.rotate(clockwise: false)
        for _ in 0..<Board.rows { engine.softDropStep() }
        engine.rotate(clockwise: false)
        advance(engine, &tracker, by: GameEngine.lockDelay + 0.1)
        XCTAssertEqual(tracker.outcome, .passed)

        let dropped = start(lesson)
        var missed = LessonTracker(lesson: lesson)
        dropped.rotate(clockwise: false)
        dropped.hardDrop()
        feed(dropped, &missed)
        XCTAssertEqual(missed.outcome, .failed, "a plain drop is not a T-spin")
    }

    func testComboLesson() throws {
        let lesson = try lesson("combo")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        for _ in lesson.pieces {
            slide(engine, -1)
            engine.hardDrop()
            feed(engine, &tracker)
            advance(engine, &tracker, by: GameEngine.clearDuration + 0.05)
        }
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testBackToBackLesson() throws {
        let lesson = try lesson("b2b")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        for _ in lesson.pieces {
            engine.rotate(clockwise: true)
            slide(engine, 1)
            engine.hardDrop()
            feed(engine, &tracker)
            advance(engine, &tracker, by: GameEngine.clearDuration + 0.05)
        }
        XCTAssertEqual(tracker.outcome, .passed)
    }

    // MARK: Tracker

    func testAClearOnTheLastPieceCountsBeforeRunningOut() throws {
        var tracker = LessonTracker(lesson: try lesson("drop"))
        tracker.observe(.locked(piece: Piece(type: .i, origin: Point(x: 3, y: 20))))
        tracker.observe(.linesCleared(rows: [21], outcome: ClearOutcome(
            lines: 1, spin: .none, perfectClear: false, backToBack: false, combo: 0, points: 100)))
        tracker.settle()
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testAVerdictIsFinal() throws {
        var tracker = LessonTracker(lesson: try lesson("drop"))
        tracker.observe(.gameOver(reason: .topOut))
        tracker.observe(.linesCleared(rows: [21], outcome: ClearOutcome(
            lines: 1, spin: .none, perfectClear: false, backToBack: false, combo: 0, points: 100)))
        XCTAssertEqual(tracker.outcome, .failed)
    }
}
