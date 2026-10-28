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

    /// A Marathon run well under way: a colourful stack with the I piece
    /// lined up over its well.
    private func runInProgress() throws -> GameSnapshot {
        let rows = ["LLLJJSSOO.", "LZZJTSSOO.", "IZZJTTTLL.",
                    "IOOSSTZZL.", "IOO.SSJZZ.", "I....JJJ.."]
        let types: [Character: TetrominoType] = ["I": .i, "O": .o, "T": .t, "S": .s,
                                                 "Z": .z, "J": .j, "L": .l]
        var cells = [TetrominoType?](repeating: nil, count: Board.columns * Board.rows)
        for (offset, row) in rows.enumerated() {
            let y = Board.rows - 1 - offset
            for (x, mark) in row.enumerated() { cells[y * Board.columns + x] = types[mark] }
        }
        let piece = Piece(type: .i, state: .right, origin: Point(x: 7, y: 6))
        let saved = GameSnapshot(mode: .marathon, startLevel: 1, cells: cells, current: piece,
                                 holdPiece: .t, holdUsed: false, queue: [.t, .s, .l, .j, .o],
                                 pendingClearRows: [], score: 48_250, lines: 47, level: 5,
                                 combo: 2, backToBack: true, elapsed: 512,
                                 stats: RunStats(), lockResets: 0, lowestRowReached: 6,
                                 lastActionWasRotation: false, lastKickIndex: 0)
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
            stats.submit(mode: .marathon, score: 48_250, lines: 47, level: 5, time: 512,
                         reason: .topOut, runStats: RunStats())
            stats.submit(mode: .sprint, score: 9_840, lines: 40, level: 1, time: 92.41,
                         reason: .targetReached, runStats: RunStats())
            stats.submit(mode: .ultra, score: 61_200, lines: 38, level: 1, time: 180,
                         reason: .timeUp, runStats: RunStats())
            for lesson in Lesson.all.prefix(3) { stats.completeLesson(lesson) }
            let savedGames = SavedGameStore(fileURL: temp.appendingPathComponent("shots-run-\(UUID().uuidString).json"))
            let audio = AudioManager()
            let haptics = HapticsManager()

            let model = GameViewModel(mode: .marathon, settings: settings, stats: stats,
                                      savedGames: savedGames, audio: audio, haptics: haptics,
                                      localization: loc, resuming: try runInProgress())
            model.resume()

            let screens: [(String, AnyView)] = [
                ("1-game", AnyView(GameView(model: model, onExit: {}))),
                ("2-practice", AnyView(PracticeView(onStart: { _ in }))),
                ("3-tspin", AnyView(GameView(mode: .marathon, settings: settings, stats: stats,
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
