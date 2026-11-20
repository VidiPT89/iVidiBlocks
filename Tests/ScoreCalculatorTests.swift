import XCTest
@testable import iVidiBlocks

final class ScoreCalculatorTests: XCTestCase {
    func testClassicLineAwards() {
        for (lines, points) in [1:40, 2:100, 3:300, 4:1200] {
            XCTAssertEqual(ScoreCalculator.points(cells: lines * 10, rings: lines, arcs: 0, chain: 1, level: 1), points)
            XCTAssertEqual(ScoreCalculator.points(cells: lines * 10, rings: lines, arcs: 0, chain: 1, level: 3), points * 3)
        }
    }
    func testTenLinesAdvanceLevel() {
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: 9), 1)
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: 10), 2)
        XCTAssertGreaterThan(ScoreCalculator.gravityInterval(level: 1), ScoreCalculator.gravityInterval(level: 10))
        XCTAssertGreaterThan(ScoreCalculator.gravityInterval(level: 20), 0)
    }
}
