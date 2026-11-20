import XCTest
@testable import iVidiBlocks

final class LessonTests: XCTestCase {
    func testEveryClassicLessonCanBeCompleted() {
        XCTAssertEqual(Lesson.all.count, 3)
        for (index, lesson) in Lesson.all.enumerated() {
            let engine = GameEngine(mode: .orbit, random: LessonPieces(order: lesson.pieces), board: lesson.board)
            engine.startImmediately()
            if index == 1 { for _ in 0..<4 { engine.move(dx: -1) } }
            if index == 2 { engine.rotate(clockwise: true) }
            engine.hardDrop()
            var tracker = LessonTracker(lesson: lesson)
            for event in engine.drainEvents() { tracker.observe(event) }
            tracker.settle(cascading: true)
            XCTAssertEqual(tracker.outcome, .passed, lesson.id)
        }
    }
}
