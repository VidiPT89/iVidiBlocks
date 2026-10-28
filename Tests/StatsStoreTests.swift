import XCTest
@testable import iVidiBlocks

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
                        mode: GameMode = .orbit,
                        score: Int = 0,
                        shards: Int = 0,
                        level: Int = 1,
                        time: TimeInterval = 0,
                        reason: GameOverReason = .topOut,
                        runStats: RunStats = RunStats()) -> Bool {
        store.submit(mode: mode, score: score, shards: shards, level: level,
                     time: time, reason: reason, runStats: runStats)
    }

    // MARK: Records

    func testAScorelessRunIsNotARecord() {
        let store = store()
        XCTAssertFalse(submit(store, score: 0))
        XCTAssertNil(store.record(for: .orbit),
                     "topping out with nothing on the board is not a personal best")
    }

    func testTheFirstScoringRunSetsTheRecord() {
        let store = store()
        XCTAssertTrue(submit(store, score: 1200, shards: 4, level: 2))
        XCTAssertEqual(store.record(for: .orbit)?.score, 1200)
    }

    func testOnlyAHigherScoreReplacesTheRecord() {
        let store = store()
        submit(store, score: 5000)

        XCTAssertFalse(submit(store, score: 4999))
        XCTAssertEqual(store.record(for: .orbit)?.score, 5000)

        XCTAssertTrue(submit(store, score: 5001))
        XCTAssertEqual(store.record(for: .orbit)?.score, 5001)
    }

    func testSprintOnlyRecordsRunsThatReachedTheTarget() {
        let store = store()
        XCTAssertFalse(submit(store, mode: .target, score: 9000, time: 30, reason: .topOut),
                       "giving up early is not a Target time")
        XCTAssertNil(store.record(for: .target))

        XCTAssertTrue(submit(store, mode: .target, score: 9000, time: 95, reason: .targetReached))
        XCTAssertEqual(store.record(for: .target)?.time, 95)
    }

    func testSprintRanksOnTheFasterTime() {
        let store = store()
        submit(store, mode: .target, time: 95, reason: .targetReached)

        XCTAssertFalse(submit(store, mode: .target, time: 110, reason: .targetReached))
        XCTAssertEqual(store.record(for: .target)?.time, 95)

        XCTAssertTrue(submit(store, mode: .target, time: 71.5, reason: .targetReached))
        XCTAssertEqual(store.record(for: .target)?.time, 71.5)
    }

    func testRecordsAreKeptPerMode() {
        let store = store()
        submit(store, mode: .orbit, score: 800)
        submit(store, mode: .blitz, score: 30_000)

        XCTAssertEqual(store.record(for: .orbit)?.score, 800)
        XCTAssertEqual(store.record(for: .blitz)?.score, 30_000)
        XCTAssertNil(store.record(for: .target))
    }

    // MARK: Lifetime totals

    func testLifetimeTotalsAccumulateEvenForScorelessRuns() {
        let store = store()
        let run = RunStats(piecesPlaced: 40, shardsCleared: 6, ringsCleared: 1, arcsFused: 2,
                           pulses: 1, maxChain: 3)

        submit(store, score: 0, time: 30, runStats: run)
        submit(store, score: 500, time: 45, runStats: run)

        XCTAssertEqual(store.lifetime.gamesPlayed, 2)
        XCTAssertEqual(store.lifetime.piecesPlaced, 80)
        XCTAssertEqual(store.lifetime.shardsCleared, 12)
        XCTAssertEqual(store.lifetime.ringsCleared, 2)
        XCTAssertEqual(store.lifetime.arcsFused, 4)
        XCTAssertEqual(store.lifetime.pulses, 2)
        XCTAssertEqual(store.lifetime.timePlayed, 75)
    }

    func testTheLongestChainIsKeptRatherThanSummed() {
        let store = store()
        submit(store, score: 100, runStats: RunStats(maxChain: 5))
        submit(store, score: 100, runStats: RunStats(maxChain: 2))

        XCTAssertEqual(store.lifetime.bestChain, 5, "a weaker run must not lower it")
    }

    func testResetClearsEverything() {
        let store = store()
        submit(store, score: 4000, runStats: RunStats(piecesPlaced: 10))

        store.reset()

        XCTAssertNil(store.record(for: .orbit))
        XCTAssertEqual(store.lifetime, LifetimeStats())
    }

    // MARK: Persistence

    func testStatsSurviveARelaunch() {
        let first = store()
        submit(first, score: 7777, shards: 20, runStats: RunStats(piecesPlaced: 99))
        first.flush()

        let second = store()
        XCTAssertEqual(second.record(for: .orbit)?.score, 7777)
        XCTAssertEqual(second.lifetime.piecesPlaced, 99)
    }

    func testAResetIsAlsoPersisted() {
        let first = store()
        submit(first, score: 7777)
        first.reset()
        first.flush()

        XCTAssertNil(store().record(for: .orbit))
    }

    func testACorruptFileIsIgnoredRatherThanCrashing() throws {
        try Data("not json at all".utf8).write(to: fileURL)

        let store = store()
        XCTAssertNil(store.record(for: .orbit))
        XCTAssertEqual(store.lifetime, LifetimeStats())
    }
    func testDebouncedWritesCannotRestoreStatsAfterResetAndFlush() {
        let first = store()
        submit(first, score: 7777)
        first.reset()
        first.flush()
        let settled = expectation(description: "pending saves settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertNil(store().record(for: .orbit))
        XCTAssertEqual(store().lifetime.gamesPlayed, 0)
    }

}
