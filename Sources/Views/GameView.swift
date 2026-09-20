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
         audio: AudioManager,
         haptics: HapticsManager,
         localization: LocalizationManager,
         onExit: @escaping () -> Void) {
        self.onExit = onExit
        _model = StateObject(wrappedValue: GameViewModel(
            mode: mode, settings: settings, stats: stats,
            audio: audio, haptics: haptics, localization: localization
        ))
    }

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: 10) {
                topBar
                HUDView(model: model)
                board
                if settings.onScreenButtons {
                    OnScreenControls(model: model, handedness: settings.handedness)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            overlays
        }
        .animation(.easeInOut(duration: 0.25), value: settings.onScreenButtons)
        .onChange(of: colorScheme) { _, _ in refreshSceneTraits() }
        .onChange(of: settings.colorBlindMode) { _, value in scene?.colorBlindMode = value }
        .onChange(of: reduceMotion) { _, value in scene?.reduceMotion = value }
        // Leaving the app mid-piece should not cost the player the run, so it
        // is waiting on the pause screen when they come back.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
        .onAppear { if scene == nil { makeScene() } }
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
            .buttonStyle(IconButtonStyle(size: 38))
            .accessibilityLabel(loc.string(.pauseTitle))

            Spacer()

            Text(loc.string(model.mode.titleKey).uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color.brandAmber)

            Spacer()

            // Balances the pause button so the mode title stays centred.
            Color.clear.frame(width: 38, height: 38)
        }
    }

    // MARK: Board

    /// Sized explicitly rather than with `aspectRatio`, so the well always
    /// fits the space left over and never pushes anything off screen.
    private var board: some View {
        GeometryReader { proxy in
            let ratio = CGFloat(Board.columns) / CGFloat(BoardScene.visibleRows)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            ZStack {
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.brandOrange.opacity(0.28), lineWidth: 1.5)
                        )
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
        if let result = model.result {
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
        let scene = BoardScene(engine: model.engine, traits: currentTraits)
        scene.colorBlindMode = settings.colorBlindMode
        scene.reduceMotion = reduceMotion
        scene.onEvent = { event in
            Task { @MainActor in model.handle(event) }
        }
        scene.onFrame = {
            Task { @MainActor in model.syncFromEngine() }
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

    private func leave() {
        audio.play(.uiTap)
        model.pause()
        onExit()
    }
}

/// Optional button bar for players who would rather not use gestures.
private struct OnScreenControls: View {
    @ObservedObject var model: GameViewModel
    let handedness: Handedness

    @EnvironmentObject private var loc: LocalizationManager

    var body: some View {
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
        .padding(.horizontal, 4)
    }

    private var moveCluster: some View {
        HStack(spacing: 8) {
            ControlButton(symbol: "arrow.left",
                          label: loc.string(.controlsLeft)) { model.moveLeft() }
            ControlButton(symbol: "arrow.down",
                          label: loc.string(.controlsSoftDrop),
                          onPress: { model.softDrop(true) },
                          onRelease: { model.softDrop(false) })
            ControlButton(symbol: "arrow.right",
                          label: loc.string(.controlsRight)) { model.moveRight() }
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
            ControlButton(symbol: "tray.and.arrow.down",
                          label: loc.string(.controlsHold)) { model.hold() }
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

    @State private var held = false

    init(symbol: String,
         label: String,
         onPress: @escaping () -> Void,
         onRelease: (() -> Void)? = nil) {
        self.symbol = symbol
        self.label = label
        self.onPress = onPress
        self.onRelease = onRelease
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
    }
}
