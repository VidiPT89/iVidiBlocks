import XCTest
@testable import iTetris

final class StatsStoreTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func store() -> StatsStore {
        StatsStore(fileURL: fileURL)
    }

    @discardableResult
    private func submit(_ store: StatsStore,
                        mode: GameMode = .marathon,
                        score: Int = 0,
                        lines: Int = 0,
                        level: Int = 1,
                        time: TimeInterval = 0,
                        reason: GameOverReason = .topOut,
                        runStats: RunStats = RunStats()) -> Bool {
        store.submit(mode: mode, score: score, lines: lines, level: level,
                     time: time, reason: reason, runStats: runStats)
    }

    // MARK: Records

    func testAScorelessRunIsNotARecord() {
        let store = store()
        XCTAssertFalse(submit(store, score: 0))
        XCTAssertNil(store.record(for: .marathon),
                     "topping out with nothing on the board is not a personal best")
    }

    func testTheFirstScoringRunSetsTheRecord() {
        let store = store()
        XCTAssertTrue(submit(store, score: 1200, lines: 4, level: 2))
        XCTAssertEqual(store.record(for: .marathon)?.score, 1200)
    }

    func testOnlyAHigherScoreReplacesTheRecord() {
        let store = store()
        submit(store, score: 5000)

        XCTAssertFalse(submit(store, score: 4999))
        XCTAssertEqual(store.record(for: .marathon)?.score, 5000)

        XCTAssertTrue(submit(store, score: 5001))
        XCTAssertEqual(store.record(for: .marathon)?.score, 5001)
    }

    func testSprintOnlyRecordsRunsThatReachedTheTarget() {
        let store = store()
        XCTAssertFalse(submit(store, mode: .sprint, score: 9000, time: 30, reason: .topOut),
                       "giving up after 12 lines is not a 40-line time")
        XCTAssertNil(store.record(for: .sprint))

        XCTAssertTrue(submit(store, mode: .sprint, score: 9000, time: 95, reason: .targetReached))
        XCTAssertEqual(store.record(for: .sprint)?.time, 95)
    }

    func testSprintRanksOnTheFasterTime() {
        let store = store()
        submit(store, mode: .sprint, time: 95, reason: .targetReached)

        XCTAssertFalse(submit(store, mode: .sprint, time: 110, reason: .targetReached))
        XCTAssertEqual(store.record(for: .sprint)?.time, 95)

        XCTAssertTrue(submit(store, mode: .sprint, time: 71.5, reason: .targetReached))
        XCTAssertEqual(store.record(for: .sprint)?.time, 71.5)
    }

    func testRecordsAreKeptPerMode() {
        let store = store()
        submit(store, mode: .marathon, score: 800)
        submit(store, mode: .ultra, score: 30_000)

        XCTAssertEqual(store.record(for: .marathon)?.score, 800)
        XCTAssertEqual(store.record(for: .ultra)?.score, 30_000)
        XCTAssertNil(store.record(for: .sprint))
    }

    // MARK: Lifetime totals

    func testLifetimeTotalsAccumulateEvenForScorelessRuns() {
        let store = store()
        let run = RunStats(piecesPlaced: 40, linesCleared: 6, tetrises: 1, tSpins: 2, maxCombo: 3)

        submit(store, score: 0, time: 30, runStats: run)
        submit(store, score: 500, time: 45, runStats: run)

        XCTAssertEqual(store.lifetime.gamesPlayed, 2)
        XCTAssertEqual(store.lifetime.piecesPlaced, 80)
        XCTAssertEqual(store.lifetime.linesCleared, 12)
        XCTAssertEqual(store.lifetime.tetrises, 2)
        XCTAssertEqual(store.lifetime.tSpins, 4)
        XCTAssertEqual(store.lifetime.timePlayed, 75)
    }

    func testTheBestComboIsKeptRatherThanSummed() {
        let store = store()
        submit(store, score: 100, runStats: RunStats(maxCombo: 5))
        submit(store, score: 100, runStats: RunStats(maxCombo: 2))

        XCTAssertEqual(store.lifetime.bestCombo, 5, "a weaker run must not lower it")
    }

    func testResetClearsEverything() {
        let store = store()
        submit(store, score: 4000, runStats: RunStats(piecesPlaced: 10))

        store.reset()

        XCTAssertNil(store.record(for: .marathon))
        XCTAssertEqual(store.lifetime, LifetimeStats())
    }

    // MARK: Persistence

    func testStatsSurviveARelaunch() {
        let first = store()
        submit(first, score: 7777, lines: 20, runStats: RunStats(piecesPlaced: 99))
        first.flush()

        let second = store()
        XCTAssertEqual(second.record(for: .marathon)?.score, 7777)
        XCTAssertEqual(second.lifetime.piecesPlaced, 99)
    }

    func testAResetIsAlsoPersisted() {
        let first = store()
        submit(first, score: 7777)
        first.reset()
        first.flush()

        XCTAssertNil(store().record(for: .marathon))
    }

    func testACorruptFileIsIgnoredRatherThanCrashing() throws {
        try Data("not json at all".utf8).write(to: fileURL)

        let store = store()
        XCTAssertNil(store.record(for: .marathon))
        XCTAssertEqual(store.lifetime, LifetimeStats())
    }
}
