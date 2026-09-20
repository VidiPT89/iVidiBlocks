import XCTest
@testable import iTetris

final class ScoreCalculatorTests: XCTestCase {

    private func points(_ lines: Int,
                        spin: SpinKind = .none,
                        perfect: Bool = false,
                        level: Int = 1,
                        b2b: Bool = false,
                        combo: Int = 0) -> Int {
        ScoreCalculator.points(lines: lines, spin: spin, perfectClear: perfect,
                               level: level, backToBack: b2b, combo: combo)
    }

    func testPlainLineClears() {
        XCTAssertEqual(points(1), 100)
        XCTAssertEqual(points(2), 300)
        XCTAssertEqual(points(3), 500)
        XCTAssertEqual(points(4), 800)
    }

    func testTSpinValues() {
        XCTAssertEqual(points(0, spin: .full), 400)
        XCTAssertEqual(points(1, spin: .full), 800)
        XCTAssertEqual(points(2, spin: .full), 1200)
        XCTAssertEqual(points(3, spin: .full), 1600)
    }

    func testTSpinMiniValues() {
        XCTAssertEqual(points(0, spin: .mini), 100)
        XCTAssertEqual(points(1, spin: .mini), 200)
    }

    func testPerfectClearValues() {
        XCTAssertEqual(points(1, perfect: true), 800)
        XCTAssertEqual(points(2, perfect: true), 1200)
        XCTAssertEqual(points(3, perfect: true), 1800)
        XCTAssertEqual(points(4, perfect: true), 2000)
    }

    func testLevelMultipliesTheBaseValue() {
        XCTAssertEqual(points(4, level: 5), 4000)
        XCTAssertEqual(points(1, level: 10), 1000)
    }

    func testBackToBackAddsHalfAgain() {
        XCTAssertEqual(points(4, b2b: true), 1200)
        XCTAssertEqual(points(2, spin: .full, b2b: true), 1800)
    }

    func testComboAddsFiftyPerChainStep() {
        XCTAssertEqual(points(1, combo: 1), 150)
        XCTAssertEqual(points(1, combo: 3), 250)
        XCTAssertEqual(points(1, level: 2, combo: 2), 400)
    }

    func testComboIsIgnoredWhenNoLinesAreCleared() {
        XCTAssertEqual(points(0, spin: .full, combo: 5), 400)
    }

    func testDropPoints() {
        XCTAssertEqual(ScoreCalculator.softDropPoints(rows: 7), 7)
        XCTAssertEqual(ScoreCalculator.hardDropPoints(rows: 7), 14)
    }

    func testGravityStartsAtOneSecondAndSpeedsUp() {
        XCTAssertEqual(ScoreCalculator.gravityInterval(level: 1), 1.0, accuracy: 0.0001)
        for level in 2...20 {
            XCTAssertLessThan(ScoreCalculator.gravityInterval(level: level),
                              ScoreCalculator.gravityInterval(level: level - 1),
                              "level \(level) should be faster than \(level - 1)")
        }
    }

    func testGravityIsCappedAtLevelTwenty() {
        let capped = ScoreCalculator.gravityInterval(level: 20)
        XCTAssertEqual(ScoreCalculator.gravityInterval(level: 30), capped, accuracy: 0.0001)
        XCTAssertGreaterThan(capped, 0)
    }

    func testLevelRisesEveryTenLines() {
        XCTAssertEqual(ScoreCalculator.level(forTotalLines: 0), 1)
        XCTAssertEqual(ScoreCalculator.level(forTotalLines: 9), 1)
        XCTAssertEqual(ScoreCalculator.level(forTotalLines: 10), 2)
        XCTAssertEqual(ScoreCalculator.level(forTotalLines: 45), 5)
    }

    func testDifficultClearsAreFlaggedForBackToBack() {
        XCTAssertTrue(ClearOutcome(lines: 4, spin: .none, perfectClear: false,
                                   backToBack: false, combo: 0, points: 0).isDifficult)
        XCTAssertTrue(ClearOutcome(lines: 1, spin: .full, perfectClear: false,
                                   backToBack: false, combo: 0, points: 0).isDifficult)
        XCTAssertFalse(ClearOutcome(lines: 3, spin: .none, perfectClear: false,
                                    backToBack: false, combo: 0, points: 0).isDifficult)
        XCTAssertFalse(ClearOutcome(lines: 0, spin: .full, perfectClear: false,
                                    backToBack: false, combo: 0, points: 0).isDifficult)
    }
}
