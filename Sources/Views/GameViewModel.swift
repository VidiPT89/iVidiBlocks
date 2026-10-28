import SwiftUI
import Combine

/// A short-lived caption shown over the board after a notable clear.
struct Banner {
    let text: String
    let accent: BannerAccent
    var detail: String?

    enum BannerAccent {
        case orange, purple, amber

        var color: Color {
            switch self {
            case .orange: return .brandOrange
            case .purple: return Color("PieceT")
            case .amber: return .brandAmber
            }
        }
    }
}

/// Bridges the pure engine to SwiftUI. The scene drives the clock and hands
/// events here; this object turns them into published state, sound and
/// haptics, and decides when a run is over.
@MainActor
final class GameViewModel: ObservableObject {

    let mode: GameMode
    private(set) var engine: GameEngine

    @Published private(set) var score = 0
    @Published private(set) var lines = 0
    @Published private(set) var level = 1
    @Published private(set) var combo = 0
    @Published private(set) var backToBack = false
    @Published private(set) var canHold = false
    @Published private(set) var holdPiece: TetrominoType?
    @Published private(set) var preview: [TetrominoType] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var timeRemaining: TimeInterval?
    @Published private(set) var linesRemaining: Int?
    @Published private(set) var isPaused = false
    @Published private(set) var banner: Banner?
    @Published private(set) var result: GameResult?
    @Published private(set) var countdownText: String?
    /// The current practice drill, or `nil` in a normal run.
    @Published private(set) var lesson: Lesson?
    /// Set once a practice attempt has been won or lost.
    @Published private(set) var lessonOutcome: LessonTracker.Outcome?

    struct GameResult: Equatable {
        let reason: GameOverReason
        let score: Int
        let lines: Int
        let level: Int
        let time: TimeInterval
        let isNewRecord: Bool
    }

    private let settings: SettingsStore
    private let stats: StatsStore
    private let savedGames: SavedGameStore
    private let audio: AudioManager
    private let haptics: HapticsManager
    private let localization: LocalizationManager
    private var heldDirections: [Int] = []
    private var bannerDismiss: Task<Void, Never>?
    private var tracker: LessonTracker?
    private var lessonVerdict: Task<Void, Never>?

    init(mode: GameMode,
         settings: SettingsStore,
         stats: StatsStore,
         savedGames: SavedGameStore,
         audio: AudioManager,
         haptics: HapticsManager,
         localization: LocalizationManager,
         resuming saved: GameSnapshot? = nil,
         lesson: Lesson? = nil) {
        self.mode = mode
        self.settings = settings
        self.stats = stats
        self.savedGames = savedGames
        self.audio = audio
        self.haptics = haptics
        self.localization = localization
        self.lesson = lesson
        tracker = lesson.map(LessonTracker.init)
        if let lesson {
            engine = Self.makeEngine(for: lesson, config: settings.gameConfig)
        } else if let saved, saved.mode == mode,
           let restored = GameEngine(restoring: saved, config: settings.gameConfig) {
            engine = restored
        } else {
            engine = GameEngine(mode: mode, config: settings.gameConfig)
        }

        haptics.enabled = settings.hapticsEnabled
        audio.sfxEnabled = settings.sfxEnabled
        level = engine.level
        countdownText = readyCaption
        preview = upcomingPieces
        timeRemaining = engine.timeRemaining
        linesRemaining = engine.linesRemaining

        // A restored run waits on the pause screen until the player is ready.
        if engine.phase == .paused {
            isPaused = true
            audio.pauseAll()
            syncFromEngine(engine)
        }
    }

    /// A drill runs on Marathon rules at level 1, with its own stack and
    /// pieces. It is never saved or recorded.
    private static func makeEngine(for lesson: Lesson, config: GameConfig) -> GameEngine {
        GameEngine(mode: .marathon, config: config,
                   random: LessonPieces(order: lesson.pieces), board: lesson.board)
    }

    /// Throws the current run away and builds a fresh engine with whatever
    /// the settings say now.
    func restart() {
        bannerDismiss?.cancel()
        lessonVerdict?.cancel()
        lessonVerdict = nil
        heldDirections = []
        canHold = false
        if let lesson {
            tracker = LessonTracker(lesson: lesson)
            lessonOutcome = nil
            engine = Self.makeEngine(for: lesson, config: settings.gameConfig)
        } else {
            savedGames.clear()
            engine = GameEngine(mode: mode, config: settings.gameConfig)
        }
        haptics.enabled = settings.hapticsEnabled
        audio.sfxEnabled = settings.sfxEnabled

        score = 0
        lines = 0
        level = settings.gameConfig.startLevel
        combo = 0
        backToBack = false
        holdPiece = nil
        preview = upcomingPieces
        elapsed = 0
        timeRemaining = engine.timeRemaining
        linesRemaining = engine.linesRemaining
        isPaused = false
        banner = nil
        result = nil
        countdownText = readyCaption
        audio.resumeAll()
    }

    // MARK: Frame sync

    /// Copies engine state into published properties once per frame. Each
    /// assignment is guarded so an unchanged value never republishes and
    /// forces SwiftUI to redraw the HUD for nothing.
    func syncFromEngine(_ source: GameEngine) {
        guard source === engine else { return }
        if score != engine.score { score = engine.score }
        if lines != engine.lines { lines = engine.lines }
        if level != engine.level { level = engine.level }
        if combo != max(engine.combo, 0) { combo = max(engine.combo, 0) }
        if backToBack != engine.backToBack { backToBack = engine.backToBack }
        if canHold != engine.canHold { canHold = engine.canHold }
        if holdPiece != engine.holdPiece { holdPiece = engine.holdPiece }
        if preview != upcomingPieces { preview = upcomingPieces }
        // Only Sprint displays elapsed time. Ultra displays whole seconds;
        // Marathon needs no clock-driven SwiftUI updates at all.
        let displayElapsed = mode == .sprint ? engine.elapsed : 0
        let displayRemaining = engine.timeRemaining.map { ceil($0) }
        if elapsed != displayElapsed { elapsed = displayElapsed }
        if timeRemaining != displayRemaining { timeRemaining = displayRemaining }
        if linesRemaining != engine.linesRemaining { linesRemaining = engine.linesRemaining }
        if countdownText != readyCaption { countdownText = readyCaption }
        judgeLesson()
    }

    /// Moves on to the next drill, or stays put after the last one.
    func startNextLesson() {
        guard let next = lesson?.next else { return }
        lesson = next
        restart()
    }

    private func judgeLesson() {
        guard var tracker, lessonOutcome == nil, lessonVerdict == nil else { return }
        tracker.settle()
        self.tracker = tracker
        let outcome = tracker.outcome
        guard outcome != .inProgress, let lesson else { return }

        if outcome == .passed {
            stats.completeLesson(lesson)
            audio.play(.levelUp)
            haptics.newRecord()
        } else {
            haptics.gameOver()
        }
        // Long enough for the clear and its banner to land before the card.
        let source = engine
        lessonVerdict = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(outcome == .passed ? 900 : 500))
            guard let self, !Task.isCancelled, source === self.engine else { return }
            self.lessonVerdict = nil
            source.pause()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                self.lessonOutcome = outcome
            }
        }
    }

    /// A drill only previews the pieces it still has to deal; the bag's
    /// filler after them would promise pieces that never come.
    private var upcomingPieces: [TetrominoType] {
        guard let lesson else { return engine.preview }
        return Array(engine.preview.prefix(max(0, lesson.pieces.count - engine.piecesDealt)))
    }

    private var readyCaption: String? {
        guard engine.phase == .ready else { return nil }
        return localization.string(.gameReady)
    }

    func handle(_ event: GameEvent, from source: GameEngine) {
        guard source === engine else { return }
        tracker?.observe(event)
        switch event {
        case .moved:
            audio.play(.move)
            haptics.move()
        case .rotated:
            audio.play(.rotate)
            haptics.rotate()
        case .hardDropped:
            audio.play(.hardDrop)
            haptics.hardDrop()
        case .locked:
            audio.play(.lock)
            haptics.lock()
        case .holdSwapped:
            audio.play(.hold)
            haptics.hold()
        case let .linesCleared(_, outcome):
            present(outcome)
        case let .levelUp(newLevel):
            audio.play(.levelUp)
            haptics.levelUp()
            show(Banner(text: localization.string(.gameLevelUp),
                        accent: .amber,
                        detail: "\(localization.string(.hudLevel)) \(newLevel)"))
        case let .gameOver(reason):
            if lesson == nil { finish(reason: reason) }
        case .spawned, .softDropped, .rotationFailed, .holdRejected:
            break
        }
    }

    private func present(_ outcome: ClearOutcome) {
        audio.play(.clear(outcome.lines))
        if outcome.spin != .none {
            audio.play(.tSpin)
            haptics.tSpin()
        } else if outcome.lines == 4 {
            haptics.quad()
        }
        if outcome.perfectClear { audio.play(.perfectClear) }

        guard let key = outcome.bannerKey else { return }
        let accent: Banner.BannerAccent
        switch outcome.spin {
        case .none: accent = outcome.lines == 4 ? .orange : .amber
        case .mini, .full: accent = .purple
        }

        var details = ["+\(outcome.points.formatted())"]
        if outcome.backToBack { details.append(localization.string(.hudBackToBack)) }
        if outcome.combo > 0 {
            details.append("\(localization.string(.hudCombo)) \(outcome.combo)")
        }
        show(Banner(text: localization.string(key), accent: accent,
                    detail: details.joined(separator: " · ")))
    }

    private func show(_ banner: Banner) {
        bannerDismiss?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.banner = banner
        }
        bannerDismiss = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.banner = nil }
        }
    }

    // MARK: Controls

    func pause() {
        guard result == nil, lessonOutcome == nil, !isPaused else { return }
        heldDirections = []
        engine.pause()
        isPaused = true
        audio.pauseAll()
    }

    func resume() {
        guard isPaused else { return }
        engine.resume()
        isPaused = false
        audio.resumeAll()
    }

    func horizontalInput(_ direction: Int, pressed: Bool) {
        guard direction == -1 || direction == 1 else { return }
        guard !pressed || engine.phase == .playing || engine.phase == .clearing else { return }
        heldDirections.removeAll { $0 == direction }
        if pressed { heldDirections.append(direction) }
        // Most recently pressed wins; releasing it restores the other held key.
        engine.setHorizontalInput(heldDirections.last ?? 0)
    }
    func rotateClockwise() { engine.rotate(clockwise: true) }
    func rotateCounterClockwise() { engine.rotate(clockwise: false) }
    func softDrop(_ active: Bool) { engine.setSoftDrop(active) }
    func hardDrop() { engine.hardDrop() }
    func hold() { engine.hold() }

    // MARK: Saving

    /// Keeps the run for the menu's Continue card. A run still counting in,
    /// or one already over, has nothing worth keeping.
    func saveProgress() {
        guard lesson == nil else { return }
        if result == nil, let snapshot = engine.snapshot() {
            savedGames.save(snapshot)
        } else {
            savedGames.clear()
        }
    }

    // MARK: Finishing

    private func finish(reason: GameOverReason) {
        guard result == nil else { return }
        savedGames.clear()
        audio.play(.gameOver)

        let beaten = stats.submit(mode: mode,
                                  score: engine.score,
                                  lines: engine.lines,
                                  level: engine.level,
                                  time: engine.elapsed,
                                  reason: reason,
                                  runStats: engine.stats)
        if beaten { haptics.newRecord() } else { haptics.gameOver() }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            result = GameResult(reason: reason,
                                score: engine.score,
                                lines: engine.lines,
                                level: engine.level,
                                time: engine.elapsed,
                                isNewRecord: beaten)
        }
    }

    /// Title for the result panel, which differs between a loss, a finished
    /// Sprint and an expired Ultra clock.
    func resultTitle(for reason: GameOverReason) -> String {
        switch reason {
        case .topOut: return localization.string(.gameOverTitle)
        case .targetReached: return localization.string(.gameOverComplete)
        case .timeUp: return localization.string(.gameOverTimeUp)
        }
    }
}
