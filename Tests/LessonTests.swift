import XCTest
@testable import iVidiBlocks

/// Every drill has to be winnable with the shards it deals, by the moves its
/// hint describes, and has to end once those shards are spent.
final class LessonTests: XCTestCase {

    private func lesson(_ id: String) throws -> Lesson {
        try XCTUnwrap(Lesson.all.first { $0.id == id })
    }

    private func start(_ lesson: Lesson) -> GameEngine {
        let engine = GameEngine(mode: .orbit,
                                random: LessonPieces(order: lesson.pieces),
                                board: lesson.board,
                                charge: lesson.charged ? GameEngine.pulseCost : 0)
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
        tracker.settle(cascading: engine.phase == .clearing)
    }

    private func turn(_ engine: GameEngine, by sectors: Int) {
        for _ in 0..<abs(sectors) { engine.move(dx: sectors > 0 ? 1 : -1) }
    }

    // MARK: Shape of the drills

    func testEveryLessonHasWholeRingsAndStartsWithNothingToClear() {
        XCTAssertEqual(Set(Lesson.all.map(\.id)).count, Lesson.all.count)
        for lesson in Lesson.all {
            XCTAssertFalse(lesson.pieces.isEmpty, lesson.id)
            XCTAssertTrue(lesson.rings.allSatisfy { $0.count == Board.sectors }, lesson.id)
            XCTAssertTrue(lesson.board.scan().isEmpty, "\(lesson.id) starts with something to clear")
        }
        XCTAssertNil(Lesson.all.last?.next)
        XCTAssertEqual(Lesson.all.first?.next, Lesson.all[1])
    }

    // MARK: Solvable, by the moves the hints describe

    func testDropLesson() throws {
        let lesson = try lesson("drop")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testSpinLessonNeedsTheWellTurned() throws {
        let lesson = try lesson("spin")
        var engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        turn(engine, by: 8)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)

        engine = start(lesson)
        tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .failed, "dropped without turning, the shard sits on the ring")
    }

    func testRotateLessonClosesTwoRings() throws {
        let lesson = try lesson("rotate")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.rotate(clockwise: true)
        turn(engine, by: 4)
        engine.hardDrop()
        let events = engine.drainEvents()
        for event in events { tracker.observe(event) }
        XCTAssertEqual(tracker.outcome, .passed)
        XCTAssertTrue(events.contains { if case let .cleared(_, _, o) = $0 { return o.rings == 2 }; return false })
    }

    func testArcLessonFusesWithoutClosingTheRing() throws {
        let lesson = try lesson("arc")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        let events = engine.drainEvents()
        for event in events { tracker.observe(event) }
        XCTAssertEqual(tracker.outcome, .passed)
        XCTAssertTrue(events.contains { if case let .cleared(_, _, o) = $0 { return o.arcs == 1 && o.rings == 0 }; return false })
    }

    func testChainLessonWaitsForTheCascadeBeforeJudging() throws {
        let lesson = try lesson("chain")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .inProgress, "the only shard is spent, but the cascade is still to come")
        advance(engine, &tracker, by: GameEngine.clearDuration + 0.1)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    func testPulseLesson() throws {
        let lesson = try lesson("pulse")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        XCTAssertTrue(engine.canPulse)
        engine.pulse()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
    }

    // MARK: Ending

    func testRunningOutOfShardsFailsTheAttempt() throws {
        let lesson = try lesson("arc")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        turn(engine, by: 6)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .failed)
    }

    func testAVerdictIsFinal() throws {
        let lesson = try lesson("drop")
        let engine = start(lesson)
        var tracker = LessonTracker(lesson: lesson)
        engine.hardDrop()
        feed(engine, &tracker)
        XCTAssertEqual(tracker.outcome, .passed)
        tracker.observe(.gameOver(reason: .topOut))
        tracker.settle(cascading: false)
        XCTAssertEqual(tracker.outcome, .passed)
    }
}
