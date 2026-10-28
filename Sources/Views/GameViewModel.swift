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
    @Published private(set) var shards = 0
    @Published private(set) var level = 1
    @Published private(set) var chain = 0
    @Published private(set) var canPulse = false
    /// Pulse charge, 0...1.
    @Published private(set) var charge = 0.0
    @Published private(set) var preview: [Shard] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var timeRemaining: TimeInterval?
    @Published private(set) var shardsRemaining: Int?
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
        let shards: Int
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
        shardsRemaining = engine.shardsRemaining
        charge = engine.chargeFraction

        // A restored run waits on the pause screen until the player is ready.
        if engine.phase == .paused {
            isPaused = true
            audio.pauseAll()
            syncFromEngine(engine)
        }
    }

    /// A drill runs on Orbit rules at level 1, with its own well and
    /// shards. It is never saved or recorded.
    private static func makeEngine(for lesson: Lesson, config: GameConfig) -> GameEngine {
        GameEngine(mode: .orbit, config: config,
                   random: LessonPieces(order: lesson.pieces), board: lesson.board,
                   charge: lesson.charged ? GameEngine.pulseCost : 0)
    }

    /// Throws the current run away and builds a fresh engine with whatever
    /// the settings say now.
    func restart() {
        bannerDismiss?.cancel()
        lessonVerdict?.cancel()
        lessonVerdict = nil
        heldDirections = []
        canPulse = false
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
        shards = 0
        level = settings.gameConfig.startLevel
        chain = 0
        charge = engine.chargeFraction
        preview = upcomingPieces
        elapsed = 0
        timeRemaining = engine.timeRemaining
        shardsRemaining = engine.shardsRemaining
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
        if shards != engine.shards { shards = engine.shards }
        if level != engine.level { level = engine.level }
        if chain != engine.chain { chain = engine.chain }
        if canPulse != engine.canPulse { canPulse = engine.canPulse }
        if charge != engine.chargeFraction { charge = engine.chargeFraction }
        if preview != upcomingPieces { preview = upcomingPieces }
        // Only Target displays elapsed time. Blitz displays whole seconds;
        // Orbit needs no clock-driven SwiftUI updates at all.
        let displayElapsed = mode == .target ? engine.elapsed : 0
        let displayRemaining = engine.timeRemaining.map { ceil($0) }
        if elapsed != displayElapsed { elapsed = displayElapsed }
        if timeRemaining != displayRemaining { timeRemaining = displayRemaining }
        if shardsRemaining != engine.shardsRemaining { shardsRemaining = engine.shardsRemaining }
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
        tracker.settle(cascading: engine.phase == .clearing)
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

    /// A drill only previews the shards it still has to deal; the bag's
    /// filler after them would promise shards that never come.
    private var upcomingPieces: [Shard] {
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
        case let .cleared(_, _, outcome):
            present(outcome)
        case let .pulsed(_, points):
            audio.play(.pulse)
            haptics.pulse()
            show(Banner(text: localization.string(.gamePulse), accent: .amber,
                        detail: "+\(points.formatted())"))
        case .coreCharged:
            audio.play(.coreCharged)
        case let .levelUp(newLevel):
            audio.play(.levelUp)
            haptics.levelUp()
            show(Banner(text: localization.string(.gameLevelUp),
                        accent: .amber,
                        detail: "\(localization.string(.hudLevel)) \(newLevel)"))
        case let .gameOver(reason):
            if lesson == nil { finish(reason: reason) }
        case .spawned, .softDropped, .rotationFailed, .pulseRejected:
            break
        }
    }

    private func present(_ outcome: ClearOutcome) {
        audio.play(.clear(outcome.rings + outcome.arcs))
        if outcome.chain > 1 {
            audio.play(.chain)
            haptics.chain()
        } else if outcome.rings > 1 {
            haptics.bigClear()
        }

        guard let key = outcome.bannerKey else { return }
        let accent: Banner.BannerAccent
        if outcome.chain > 1 {
            accent = .purple
        } else {
            accent = outcome.rings > 0 ? .orange : .amber
        }

        var text = localization.string(key)
        if outcome.chain > 1 { text += " ×\(outcome.chain)" }
        show(Banner(text: text, accent: accent, detail: "+\(outcome.points.formatted())"))
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
    func pulse() { engine.pulse() }

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
                                  shards: engine.shards,
                                  level: engine.level,
                                  time: engine.elapsed,
                                  reason: reason,
                                  runStats: engine.stats)
        if beaten { haptics.newRecord() } else { haptics.gameOver() }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            result = GameResult(reason: reason,
                                score: engine.score,
                                shards: engine.shards,
                                level: engine.level,
                                time: engine.elapsed,
                                isNewRecord: beaten)
        }
    }

    /// Title for the result panel, which differs between a loss, a finished
    /// Target run and an expired Blitz clock.
    func resultTitle(for reason: GameOverReason) -> String {
        switch reason {
        case .topOut: return localization.string(.gameOverTitle)
        case .targetReached: return localization.string(.gameOverComplete)
        case .timeUp: return localization.string(.gameOverTimeUp)
        }
    }
}
