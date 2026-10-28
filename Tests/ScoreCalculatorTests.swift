import XCTest
@testable import iVidiBlocks

final class ScoreCalculatorTests: XCTestCase {

    func testCellsRingsAndArcsAllCount() {
        XCTAssertEqual(ScoreCalculator.points(cells: 16, rings: 1, arcs: 0, chain: 1, level: 1), 260)
        XCTAssertEqual(ScoreCalculator.points(cells: 5, rings: 0, arcs: 1, chain: 1, level: 1), 110)
    }

    func testEachChainLinkMultipliesTheWholeStep() {
        let single = ScoreCalculator.points(cells: 5, rings: 0, arcs: 1, chain: 1, level: 1)
        XCTAssertEqual(ScoreCalculator.points(cells: 5, rings: 0, arcs: 1, chain: 3, level: 1), single * 3)
    }

    func testLevelMultipliesTheScore() {
        XCTAssertEqual(ScoreCalculator.points(cells: 5, rings: 0, arcs: 1, chain: 1, level: 4), 440)
    }

    func testAPulsePaysLessThanEarningTheSameCells() {
        XCTAssertLessThan(ScoreCalculator.pulsePoints(cells: 16, level: 1),
                          ScoreCalculator.points(cells: 16, rings: 1, arcs: 0, chain: 1, level: 1))
    }

    func testGravitySpeedsUpWithLevelAndIsCapped() {
        XCTAssertGreaterThan(ScoreCalculator.gravityInterval(level: 1),
                             ScoreCalculator.gravityInterval(level: 5))
        XCTAssertEqual(ScoreCalculator.gravityInterval(level: 20),
                       ScoreCalculator.gravityInterval(level: 40))
        XCTAssertGreaterThan(ScoreCalculator.gravityInterval(level: 20), 0)
    }

    func testLevelsFollowClearedShards() {
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: 0), 1)
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: ScoreCalculator.shardsPerLevel - 1), 1)
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: ScoreCalculator.shardsPerLevel), 2)
        XCTAssertEqual(ScoreCalculator.level(forTotalShards: 0, startingAt: 5), 5)
    }

    func testBannersNameTheBiggestThingThatHappened() {
        func outcome(rings: Int = 0, arcs: Int = 0, chain: Int = 1) -> ClearOutcome {
            ClearOutcome(cells: 5, rings: rings, arcs: arcs, chain: chain, points: 0)
        }
        XCTAssertEqual(outcome(arcs: 1).bannerKey, .gameArc)
        XCTAssertEqual(outcome(rings: 1).bannerKey, .gameRing)
        XCTAssertEqual(outcome(rings: 2).bannerKey, .gameRings)
        XCTAssertEqual(outcome(rings: 2, chain: 2).bannerKey, .gameChain)
    }
}
