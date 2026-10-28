import XCTest
@testable import iVidiBlocks

@MainActor
final class GameViewModelTests: XCTestCase {
    private static let audio = AudioManager()
    private static let haptics = HapticsManager()
    private func makeModel(_ mode: GameMode = .orbit,
                           savedGames: SavedGameStore? = nil,
                           resuming saved: GameSnapshot? = nil,
                           lesson: Lesson? = nil) -> (GameViewModel, StatsStore) {
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
                                  resuming: saved,
                                  lesson: lesson)
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
        model.handle(.cleared(cells: [], colors: [], outcome: ClearOutcome(
            cells: 16, rings: 1, arcs: 0, chain: 1, points: 260)), from: old)
        XCTAssertNil(model.banner)
    }

    func testOrbitDoesNotPublishAnUnusedClock() async {
        let (model, _) = makeModel()
        model.engine.startImmediately()
        model.engine.update(deltaTime: 0.2)
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertEqual(model.engine.elapsed, 0.2)
    }

    func testBlitzOnlyPublishesWholeCountdownSeconds() async {
        let (model, _) = makeModel(.blitz)
        model.engine.startImmediately()
        model.engine.update(deltaTime: 0.2)
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.timeRemaining, 120)
        XCTAssertEqual(model.elapsed, 0)
    }

    func testTargetKeepsPreciseElapsedTime() async {
        let (model, _) = makeModel(.target)
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

    func testPulseAvailabilityFollowsTheChargeAndResetsOnRestart() async throws {
        let lesson = try XCTUnwrap(Lesson.all.first { $0.charged })
        let (model, _) = makeModel(lesson: lesson)
        model.engine.startImmediately()
        model.syncFromEngine(model.engine)
        XCTAssertTrue(model.canPulse)
        XCTAssertEqual(model.charge, 1)
        model.pulse()
        model.syncFromEngine(model.engine)
        XCTAssertFalse(model.canPulse)
        XCTAssertEqual(model.charge, 0)
        model.restart()
        XCTAssertFalse(model.canPulse)
    }

    func testAChainBannerNamesTheLinkAndThePoints() async throws {
        let (model, _) = makeModel()
        model.handle(.cleared(cells: [], colors: [], outcome: ClearOutcome(
            cells: 6, rings: 0, arcs: 1, chain: 3, points: 1080)), from: model.engine)
        let banner = try XCTUnwrap(model.banner)
        XCTAssertTrue(banner.text.hasSuffix("×3"))
        XCTAssertTrue(try XCTUnwrap(banner.detail).contains(1080.formatted()))
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

    // MARK: Practice

    func testAPracticeDrillIsNeitherSavedNorRecorded() async throws {
        let store = runStore()
        let lesson = try XCTUnwrap(Lesson.all.first)
        let (model, stats) = makeModel(savedGames: store, lesson: lesson)
        model.engine.startImmediately()
        model.saveProgress()
        XCTAssertNil(store.snapshot)
        model.handle(.gameOver(reason: .topOut), from: model.engine)
        XCTAssertNil(model.result)
        XCTAssertEqual(stats.lifetime.gamesPlayed, 0)
    }

    func testADrillPreviewsOnlyTheShardsItStillDeals() async throws {
        let lesson = try XCTUnwrap(Lesson.all.first { $0.id == "pulse" })
        let (model, _) = makeModel(lesson: lesson)
        XCTAssertEqual(model.preview.count, 3)
        model.engine.startImmediately()
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.preview.count, 2)
        model.engine.hardDrop()
        model.syncFromEngine(model.engine)
        XCTAssertEqual(model.preview.count, 1)
    }

    func testPassingADrillMarksItDoneAndAnnouncesTheResult() async throws {
        let lesson = try XCTUnwrap(Lesson.all.first)
        let (model, stats) = makeModel(lesson: lesson)
        model.engine.startImmediately()
        model.engine.hardDrop()
        for event in model.engine.drainEvents() { model.handle(event, from: model.engine) }
        model.syncFromEngine(model.engine)
        XCTAssertTrue(stats.completedLessons.contains(lesson.id))
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(model.lessonOutcome, .passed)

        model.startNextLesson()
        XCTAssertEqual(model.lesson, lesson.next)
        XCTAssertNil(model.lessonOutcome)
    }
}
