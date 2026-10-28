import XCTest
@testable import iTetris

@MainActor
final class GameViewModelTests: XCTestCase {
    private static let audio = AudioManager()
    private static let haptics = HapticsManager()
    private func makeModel(_ mode: GameMode = .marathon,
                           savedGames: SavedGameStore? = nil,
                           resuming saved: GameSnapshot? = nil) -> (GameViewModel, StatsStore) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.musicEnabled = false
        settings.sfxEnabled = false
        settings.hapticsEnabled = false
        let stats = StatsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("model-\(UUID().uuidString).json"))
        let store = savedGames ?? SavedGameStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("model-run-\(UUID().uuidString).json"))
        let model = GameViewModel(mode: mode, settings: settings, stats: stats,
                                  savedGames: store,
                                  audio: Self.audio, haptics: Self.haptics,
                                  localization: LocalizationManager(defaults: defaults),
                                  resuming: saved)
        return (model, stats)
    }

    func testOldGameOverCannotFinishOrRecordARestartedRun() async {
        let (model, stats) = makeModel()
        let old = model.engine
        model.restart()
        model.handle(.gameOver(reason: .topOut), from: old)
        XCTAssertNil(model.result)
        XCTAssertEqual(stats.lifetime.gamesPlayed, 0)
    }

    func testOldClearCannotShowABannerInANewRun() async {
        let (model, _) = makeModel()
        let old = model.engine
        model.restart()
        model.handle(.linesCleared(rows: [21], outcome: ClearOutcome(
            lines: 1, spin: .none, perfectClear: false,
            backToBack: false, combo: 0, points: 100)), from: old)
        XCTAssertNil(model.banner)
    }

    func testMarathonDoesNotPublishAnUnusedClock() async {
        let (model, _) = makeModel()
        model.engine.startImmediately()
        model.engine.update(deltaTime: 0.2)
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(model.engine.elapsed, 0.2)
    }

    func testUltraOnlyPublishesWholeCountdownSeconds() async {
        let (model, _) = makeModel(.ultra)
        model.engine.startImmediately()
        model.engine.update(deltaTime: 0.2)
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.timeRemaining, 180)
        XCTAssertEqual(model.elapsed, 0)
    }

    func testSprintKeepsPreciseElapsedTime() async {
        let (model, _) = makeModel(.sprint)
        model.engine.startImmediately()
        model.engine.update(deltaTime: 0.125)
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.elapsed, 0.125)
    }

    func testReleasingTheOtherDirectionDoesNotStopTheHeldDirection() async throws {
        let (model, _) = makeModel()
        model.engine.startImmediately()
        model.horizontalInput(-1, pressed: true)
        model.horizontalInput(1, pressed: true)
        model.horizontalInput(-1, pressed: false)
        let before = try XCTUnwrap(model.engine.current).origin.x
        model.engine.update(deltaTime: 0.2)
        XCTAssertGreaterThan(try XCTUnwrap(model.engine.current).origin.x, before)
    }

    func testHoldAvailabilityFollowsTheEngineAndResetsOnRestart() async {
        let (model, _) = makeModel()
        model.engine.startImmediately()
        model.syncFromEngine(model.engine)
        XCTAssertTrue(model.canHold)
        model.hold()
        model.syncFromEngine(model.engine)
        XCTAssertFalse(model.canHold)
        model.engine.hardDrop()
        model.syncFromEngine(model.engine)
        XCTAssertTrue(model.canHold)
        model.restart()
        XCTAssertFalse(model.canHold)
    }

    func testClearBannerIncludesPointsAndBothChainBonuses() async throws {
        let (model, _) = makeModel()
        model.handle(.linesCleared(rows: [18, 19, 20, 21], outcome: ClearOutcome(
            lines: 4, spin: .none, perfectClear: false,
            backToBack: true, combo: 2, points: 1300)), from: model.engine)
        let detail = try XCTUnwrap(model.banner?.detail)
        XCTAssertTrue(detail.contains(1300.formatted()))
        XCTAssertEqual(detail.components(separatedBy: " · ").count, 3)
    }

    // MARK: Saved runs

    private func runStore() -> SavedGameStore {
        SavedGameStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("model-run-\(UUID().uuidString).json"))
    }

    func testSavingKeepsARunInProgressAndRestartDropsIt() async {
        let store = runStore()
        let (model, _) = makeModel(savedGames: store)
        model.saveProgress()
        XCTAssertNil(store.snapshot, "nothing to keep before the first piece")

        model.engine.startImmediately()
        model.engine.hardDrop()
        model.pause()
        model.saveProgress()
        XCTAssertEqual(store.snapshot, model.engine.snapshot())

        model.restart()
        XCTAssertNil(store.snapshot)
    }

    func testAResumedRunWaitsOnThePauseScreenWithItsNumbers() async throws {
        let (source, _) = makeModel()
        source.engine.startImmediately()
        source.engine.hardDrop()
        let saved = try XCTUnwrap(source.engine.snapshot())

        let (model, _) = makeModel(resuming: saved)
        XCTAssertTrue(model.isPaused)
        XCTAssertEqual(model.score, saved.score)
        XCTAssertNil(model.countdownText)
        model.resume()
        XCTAssertEqual(model.engine.phase, .playing)
    }

    func testFinishingARunDropsTheSave() async {
        let store = runStore()
        let (model, _) = makeModel(savedGames: store)
        model.engine.startImmediately()
        model.saveProgress()
        XCTAssertNotNil(store.snapshot)
        model.handle(.gameOver(reason: .topOut), from: model.engine)
        XCTAssertNil(store.snapshot)
    }
}
