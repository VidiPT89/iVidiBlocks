import XCTest
import SwiftUI
@testable import iVidiBlocks

/// Renders the App Store screenshots as test attachments. Skipped unless
/// the run sets `SCREENSHOTS=1` (pass `TEST_RUNNER_SCREENSHOTS=1` to
/// xcodebuild), so the everyday suite stays fast.
@MainActor
final class StoreScreenshotTests: XCTestCase {

    private struct Device {
        let name: String
        let points: CGSize
        let scale: CGFloat
    }

    private let devices = [
        Device(name: "iphone", points: CGSize(width: 402, height: 874), scale: 3),
        Device(name: "ipad", points: CGSize(width: 1032, height: 1376), scale: 2)
    ]

    /// An Orbit run well under way: a colourful well with a bent shard on
    /// its way in and the core two-thirds charged.
    private func runInProgress() throws -> GameSnapshot {
        let rings = ["eatteaat.ettaeat", "taeat.ettaa.teae",
                     "at.e.aatt..eat..", "ea.t.a.t...at..."]
        let colors: [Character: ShardColor] = ["e": .ember, "a": .amber, "t": .tide]
        var board = Board()
        for (offset, ring) in rings.enumerated() {
            for (x, mark) in ring.enumerated() { board[x, Board.rings - 1 - offset] = colors[mark] }
        }
        XCTAssertTrue(board.scan().isEmpty)
        let piece = Piece(shard: Shard(shape: .bend, color: .tide), origin: Point(x: 2, y: 4))
        let saved = GameSnapshot(mode: .orbit, startLevel: 1, cells: board.cells, current: piece,
                                 aim: 2, queue: Array(Shard.all.prefix(6)),
                                 pendingClear: [], chain: 0, charge: 24, score: 18_420,
                                 shards: 150, level: ScoreCalculator.level(forTotalShards: 150),
                                 elapsed: 512, stats: RunStats(), lockResets: 0, lowestRingReached: 4)
        XCTAssertNotNil(GameEngine(restoring: saved))
        return saved
    }

    func testStoreScreenshots() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1")

        for language in AppLanguage.allCases {
            let defaults = UserDefaults(suiteName: UUID().uuidString)!
            let settings = SettingsStore(defaults: defaults)
            settings.theme = .dark
            settings.musicEnabled = false
            settings.sfxEnabled = false
            settings.hapticsEnabled = false
            let loc = LocalizationManager(defaults: defaults)
            loc.setLanguage(language)
            let temp = FileManager.default.temporaryDirectory
            let stats = StatsStore(fileURL: temp.appendingPathComponent("shots-\(UUID().uuidString).json"))
            stats.submit(mode: .orbit, score: 18_420, shards: 150, level: 4, time: 512,
                         reason: .topOut, runStats: RunStats())
            stats.submit(mode: .target, score: 9_840, shards: 160, level: 1, time: 141.6,
                         reason: .targetReached, runStats: RunStats())
            stats.submit(mode: .blitz, score: 21_300, shards: 131, level: 1, time: 120,
                         reason: .timeUp, runStats: RunStats())
            for lesson in Lesson.all.prefix(3) { stats.completeLesson(lesson) }
            let savedGames = SavedGameStore(fileURL: temp.appendingPathComponent("shots-run-\(UUID().uuidString).json"))
            let audio = AudioManager()
            let haptics = HapticsManager()

            let model = GameViewModel(mode: .orbit, settings: settings, stats: stats,
                                      savedGames: savedGames, audio: audio, haptics: haptics,
                                      localization: loc, resuming: try runInProgress())
            model.resume()

            let screens: [(String, AnyView)] = [
                ("1-game", AnyView(GameView(model: model, onExit: {}))),
                ("2-practice", AnyView(PracticeView(onStart: { _ in }))),
                ("3-chain", AnyView(GameView(mode: .orbit, settings: settings, stats: stats,
                                             savedGames: savedGames, audio: audio, haptics: haptics,
                                             localization: loc, lesson: Lesson.all[4], onExit: {}))),
                ("4-menu", AnyView(ZStack {
                    BrandBackground()
                    MainMenuView(onPlay: { _, _ in }, onPractice: { _ in })
                }))
            ]
            for device in devices {
                for (name, view) in screens {
                    let root = view
                        .environmentObject(settings).environmentObject(loc)
                        .environmentObject(audio).environmentObject(stats)
                        .environmentObject(savedGames)
                        .environment(\.colorScheme, .dark)
                        .environment(\.locale, language.locale)
                        .tint(.brandOrange)
                    let controller = UIHostingController(rootView: root)
                    let window = UIWindow(frame: CGRect(origin: .zero, size: device.points))
                    window.rootViewController = controller
                    window.isHidden = false
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(2200))
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = device.scale
                    format.opaque = true
                    let image = UIGraphicsImageRenderer(size: device.points, format: format).image { _ in
                        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                    }
                    window.isHidden = true
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "\(language.rawValue)-\(device.name)-\(name)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }
}
