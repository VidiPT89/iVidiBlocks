import SwiftUI

@main
struct iTetrisApp: App {
    @StateObject private var localization = LocalizationManager()
    @StateObject private var settings = SettingsStore()
    @StateObject private var stats = StatsStore()
    @StateObject private var audio = AudioManager()
    @StateObject private var haptics = HapticsManager()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(localization)
                .environmentObject(settings)
                .environmentObject(stats)
                .environmentObject(audio)
                .environmentObject(haptics)
                .preferredColorScheme(settings.theme.colorScheme)
                .environment(\.locale, localization.language.locale)
                .tint(.brandOrange)
        }
        // Coming back is deliberately not handled here: a game that was
        // interrupted returns to its pause screen, and starting the music
        // again is the job of whichever screen the player lands on.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            audio.pauseAll()
            stats.flush()
        }
    }
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
