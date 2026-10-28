import XCTest
import SwiftUI
@testable import iVidiBlocks

@MainActor
final class LayoutTests: XCTestCase {
    func testGameLayoutsOnSmallPhoneAndTablet() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.onScreenButtons = true
        settings.musicEnabled = false
        settings.sfxEnabled = false
        settings.hapticsEnabled = false
        let loc = LocalizationManager(defaults: defaults)
        loc.setLanguage(.pt)
        let stats = StatsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString).json"))
        let savedGames = SavedGameStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-run-\(UUID().uuidString).json"))
        let audio = AudioManager()
        let haptics = HapticsManager()
        for (name, size, scheme, handedness) in [
            ("small-phone-dark-right", CGSize(width: 320, height: 568), ColorScheme.dark, Handedness.right),
            ("tablet-light-left", CGSize(width: 768, height: 1024), ColorScheme.light, Handedness.left)
        ] {
            settings.handedness = handedness
            let root = GameView(mode: .marathon, settings: settings, stats: stats,
                                savedGames: savedGames, audio: audio, haptics: haptics, localization: loc, onExit: {})
                .environmentObject(settings).environmentObject(loc).environmentObject(audio)
                .environment(\.colorScheme, scheme)
            let controller = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(1400))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(controller.view.bounds.size, size)
        }
    }

    func testMenuPracticeAndDrillLayouts() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = SettingsStore(defaults: defaults)
        settings.musicEnabled = false
        settings.sfxEnabled = false
        settings.hapticsEnabled = false
        let loc = LocalizationManager(defaults: defaults)
        loc.setLanguage(.pt)
        let stats = StatsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString).json"))
        let savedGames = SavedGameStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-run-\(UUID().uuidString).json"))
        let engine = GameEngine(mode: .sprint)
        engine.startImmediately()
        engine.hardDrop()
        savedGames.save(try XCTUnwrap(engine.snapshot()))
        stats.completeLesson(Lesson.all[0])
        let audio = AudioManager()
        let haptics = HapticsManager()
        let size = CGSize(width: 375, height: 667)

        let screens: [(String, AnyView)] = [
            ("menu-saved-run", AnyView(MainMenuView(onPlay: { _, _ in }, onPractice: { _ in }))),
            ("practice-list", AnyView(PracticeView(onStart: { _ in }))),
            ("drill-tspin", AnyView(GameView(mode: .marathon, settings: settings, stats: stats,
                                             savedGames: savedGames, audio: audio, haptics: haptics,
                                             localization: loc, lesson: Lesson.all[4], onExit: {})))
        ]
        for (name, view) in screens {
            let root = view
                .environmentObject(settings).environmentObject(loc).environmentObject(audio)
                .environmentObject(stats).environmentObject(savedGames)
                .environment(\.colorScheme, .dark)
            let controller = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(1600))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
