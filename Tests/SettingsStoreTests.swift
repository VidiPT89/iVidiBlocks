import XCTest
@testable import iTetris

final class SettingsStoreTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "settings-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testFreshInstallUsesTheDocumentedDefaults() {
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.theme, .system)
        XCTAssertTrue(settings.ghostEnabled)
        XCTAssertEqual(settings.das, SettingsStore.defaultDas)
        XCTAssertEqual(settings.arr, SettingsStore.defaultArr)
        XCTAssertFalse(settings.onScreenButtons)
        XCTAssertEqual(settings.handedness, .right)
        XCTAssertFalse(settings.colorBlindMode)
    }

    func testChangesSurviveARelaunch() {
        let first = SettingsStore(defaults: defaults)
        first.theme = .dark
        first.ghostEnabled = false
        first.handedness = .left
        first.das = 0.2

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertFalse(second.ghostEnabled)
        XCTAssertEqual(second.handedness, .left)
        XCTAssertEqual(second.das, 0.2)
    }

    func testAnOutOfRangeDelayIsPulledBackIntoRange() {
        defaults.set(0.0, forKey: "settings.das")
        defaults.set(99.0, forKey: "settings.arr")

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.das, SettingsStore.dasRange.lowerBound)
        XCTAssertEqual(settings.arr, SettingsStore.arrRange.upperBound)
    }

    func testANonsenseDelayFallsBackToTheDefault() {
        defaults.set(Double.nan, forKey: "settings.das")

        XCTAssertEqual(SettingsStore(defaults: defaults).das, SettingsStore.defaultDas)
    }

    func testAnUnknownStoredThemeFallsBackToSystem() {
        defaults.set("sepia", forKey: "settings.theme")

        XCTAssertEqual(SettingsStore(defaults: defaults).theme, .system)
    }

    func testTheThemeButtonCyclesThroughAllThree() {
        XCTAssertEqual(AppTheme.system.next, .light)
        XCTAssertEqual(AppTheme.light.next, .dark)
        XCTAssertEqual(AppTheme.dark.next, .system)
    }

    func testTheEngineConfigMirrorsTheStoredPreferences() {
        let settings = SettingsStore(defaults: defaults)
        settings.das = 0.25
        settings.arr = 0.05
        settings.ghostEnabled = false

        let config = settings.gameConfig
        XCTAssertEqual(config.das, 0.25)
        XCTAssertEqual(config.arr, 0.05)
        XCTAssertFalse(config.ghostEnabled)
    }
}
