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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                audio.resumeAll()
            case .background, .inactive:
                audio.pauseAll()
                stats.flush()
            @unknown default:
                break
            }
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
