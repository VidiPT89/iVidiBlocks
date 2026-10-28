import SwiftUI
import SpriteKit

struct GameView: View {
    let onExit: () -> Void

    @EnvironmentObject private var loc: LocalizationManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var audio: AudioManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var model: GameViewModel
    @State private var scene: BoardScene?

    init(mode: GameMode,
         settings: SettingsStore,
         stats: StatsStore,
         savedGames: SavedGameStore,
         audio: AudioManager,
         haptics: HapticsManager,
         localization: LocalizationManager,
         resuming saved: GameSnapshot? = nil,
         lesson: Lesson? = nil,
         onExit: @escaping () -> Void) {
        self.onExit = onExit
        _model = StateObject(wrappedValue: GameViewModel(
            mode: mode, settings: settings, stats: stats, savedGames: savedGames,
            audio: audio, haptics: haptics, localization: localization,
            resuming: saved, lesson: lesson
        ))
    }

    /// Wraps a model that already exists, for previews and layout tests.
    init(model: GameViewModel, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: 10) {
                topBar
                if let lesson = model.lesson {
                    LessonBriefing(lesson: lesson)
                }
                HUDView(model: model)
                board
                if settings.onScreenButtons {
                    OnScreenControls(model: model, handedness: settings.handedness)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: 600)

            overlays
        }
        .animation(.easeInOut(duration: 0.25), value: settings.onScreenButtons)
        .onChange(of: colorScheme) { _, _ in refreshSceneTraits() }
        .onChange(of: settings.colorBlindMode) { _, value in scene?.colorBlindMode = value }
        .onChange(of: reduceMotion) { _, value in scene?.reduceMotion = value }
        // Leaving the app mid-piece should not cost the player the run: it
        // waits on the pause screen, and is saved in case the app is closed.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            model.pause()
            model.saveProgress()
        }
        .onAppear { if scene == nil { makeScene() } }
        .onDisappear {
            scene?.onEvent = nil
            scene?.onFrame = nil
            scene = nil
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                audio.play(.uiTap)
                model.pause()
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel(loc.string(.pauseTitle))

            Spacer()

            Text(loc.string(model.lesson?.titleKey ?? model.mode.titleKey).uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.brandAmber)

            Spacer()

            // Balances the pause button so the mode title stays centred.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    // MARK: Board

    /// Sized explicitly rather than with `aspectRatio`, so the round well
    /// always fits the space left over and never pushes anything off screen.
    private var board: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.brandOrange.opacity(0.28), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                }

                if let banner = model.banner { BannerView(banner: banner) }

                if let countdown = model.countdownText {
                    Text(countdown)
                        .font(.display(38))
                        .foregroundStyle(.brandGradient)
                        .shadow(color: .brandOrange.opacity(0.6), radius: 20)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if let lesson = model.lesson, let outcome = model.lessonOutcome {
            LessonResultView(lesson: lesson,
                             passed: outcome == .passed,
                             onRetry: restart,
                             onNext: nextLesson,
                             onExit: leave)
                .transition(.opacity)
        } else if let result = model.result {
            GameOverView(model: model, result: result,
                         onPlayAgain: restart, onExit: leave)
                .transition(.opacity)
        } else if model.isPaused {
            PauseOverlay(onResume: { model.resume() },
                         onRestart: restart,
                         onQuit: leave)
                .transition(.opacity)
        }
    }

    // MARK: Scene lifecycle

    private func makeScene() {
        let source = model.engine
        let scene = BoardScene(engine: source, traits: currentTraits)
        scene.colorBlindMode = settings.colorBlindMode
        scene.reduceMotion = reduceMotion
        scene.onEvent = { [weak model] event in
            Task { @MainActor [weak model] in model?.handle(event, from: source) }
        }
        scene.onFrame = { [weak model] in
            Task { @MainActor [weak model] in model?.syncFromEngine(source) }
        }
        self.scene = scene
    }

    private var currentTraits: UITraitCollection {
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    }

    private func refreshSceneTraits() {
        scene?.applyTraits(currentTraits)
    }

    private func restart() {
        audio.play(.uiTap)
        model.restart()
        makeScene()
    }

    private func nextLesson() {
        audio.play(.uiTap)
        model.startNextLesson()
        makeScene()
    }

    private func leave() {
        audio.play(.uiTap)
        model.pause()
        model.saveProgress()
        audio.resumeAll()
        onExit()
    }
}

/// Optional button bar for players who would rather not use gestures.
private struct OnScreenControls: View {
    @ObservedObject var model: GameViewModel
    let handedness: Handedness

    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalControls
            VStack(spacing: 8) {
                actionCluster
                moveCluster
            }
        }
        .padding(.horizontal, 4)
    }

    private var horizontalControls: some View {
        HStack(spacing: 10) {
            if handedness == .left {
                actionCluster
                Spacer(minLength: 0)
                moveCluster
            } else {
                moveCluster
                Spacer(minLength: 0)
                actionCluster
            }
        }
    }

    private var moveCluster: some View {
        HStack(spacing: 8) {
            ControlButton(symbol: "arrow.left",
                          label: loc.string(.controlsLeft),
                          onPress: { model.horizontalInput(-1, pressed: true) },
                          onRelease: { model.horizontalInput(-1, pressed: false) })
            ControlButton(symbol: "arrow.down",
                          label: loc.string(.controlsSoftDrop),
                          onPress: { model.softDrop(true) },
                          onRelease: { model.softDrop(false) },
                          accessibilityPress: { model.engine.softDropStep() })
            ControlButton(symbol: "arrow.right",
                          label: loc.string(.controlsRight),
                          onPress: { model.horizontalInput(1, pressed: true) },
                          onRelease: { model.horizontalInput(1, pressed: false) })
        }
    }

    private var actionCluster: some View {
        HStack(spacing: 8) {
            ControlButton(symbol: "arrow.counterclockwise",
                          label: loc.string(.controlsRotateCCW)) { model.rotateCounterClockwise() }
            ControlButton(symbol: "arrow.clockwise",
                          label: loc.string(.controlsRotateCW)) { model.rotateClockwise() }
            ControlButton(symbol: "arrow.down.to.line",
                          label: loc.string(.controlsHardDrop)) { model.hardDrop() }
            ControlButton(symbol: "dot.radiowaves.left.and.right",
                          label: loc.string(.controlsPulse)) { model.pulse() }
        }
    }
}

/// Fires on touch down rather than on release, so the board reacts in the
/// same frame the finger lands.
private struct ControlButton: View {
    let symbol: String
    let label: String
    var onPress: () -> Void
    var onRelease: (() -> Void)?
    var accessibilityPress: (() -> Void)?

    @State private var held = false

    init(symbol: String,
         label: String,
         onPress: @escaping () -> Void,
         onRelease: (() -> Void)? = nil,
         accessibilityPress: (() -> Void)? = nil) {
        self.symbol = symbol
        self.label = label
        self.onPress = onPress
        self.onRelease = onRelease
        self.accessibilityPress = accessibilityPress
    }

    init(symbol: String, label: String, action: @escaping () -> Void) {
        self.init(symbol: symbol, label: label, onPress: action, onRelease: nil)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: Layout.minimumTapTarget, height: Layout.minimumTapTarget)
            .background(Circle().fill(held ? Color.brandOrange.opacity(0.3) : Color.bgElevated))
            .overlay(Circle().strokeBorder(Color.brandOrange.opacity(0.3), lineWidth: 1))
            .scaleEffect(held ? 0.92 : 1)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !held else { return }
                        held = true
                        onPress()
                    }
                    .onEnded { _ in
                        held = false
                        onRelease?()
                    }
            )
            .animation(.easeOut(duration: 0.12), value: held)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if let accessibilityPress {
                    accessibilityPress()
                } else {
                    onPress()
                    onRelease?()
                }
            }
            .onDisappear {
                held = false
                onRelease?()
            }
    }
}
