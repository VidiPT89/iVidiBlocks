import SwiftUI

/// Top-level navigation: the splash plays once at launch, then the menu
/// owns everything else. Kept deliberately flat so a game screen is never
/// more than one transition away.
struct AppRouter: View {
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var stats: StatsStore
    @EnvironmentObject private var audio: AudioManager
    @EnvironmentObject private var haptics: HapticsManager

    @State private var showingSplash = true
    @State private var activeMode: GameMode?

    var body: some View {
        ZStack {
            BrandBackground()

            if let mode = activeMode {
                GameView(mode: mode,
                         settings: settings,
                         stats: stats,
                         audio: audio,
                         haptics: haptics,
                         localization: localization,
                         onExit: { activeMode = nil })
                    .id(mode)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.04)),
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
            } else {
                MainMenuView { mode in
                    withAnimation(.easeInOut(duration: 0.35)) { activeMode = mode }
                }
                .transition(.opacity)
            }

            if showingSplash {
                SplashView(style: .launch) {
                    withAnimation(.easeIn(duration: 0.4)) { showingSplash = false }
                }
                // Lifts towards the viewer on the way out. A plain crossfade
                // would briefly show two wordmarks at different heights.
                .transition(.scale(scale: 1.14).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: activeMode)
        .onAppear { audio.musicEnabled = settings.musicEnabled }
        .onChange(of: settings.musicEnabled) { _, enabled in audio.musicEnabled = enabled }
        .onChange(of: settings.sfxEnabled) { _, enabled in audio.sfxEnabled = enabled }
    }
}
