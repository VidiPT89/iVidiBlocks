import Foundation
import Combine

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleKey: LocKey {
        switch self {
        case .system: return .settingsThemeSystem
        case .light: return .settingsThemeLight
        case .dark: return .settingsThemeDark
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var next: AppTheme {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }
}

enum Handedness: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }

    var titleKey: LocKey {
        self == .left ? .settingsHandednessLeft : .settingsHandednessRight
    }
}

/// Every persisted preference. Writes go straight to `UserDefaults`, which
/// already coalesces them, so no debounce is needed here.
final class SettingsStore: ObservableObject {

    @Published var theme: AppTheme { didSet { write(theme.rawValue, .theme) } }
    @Published var ghostEnabled: Bool { didSet { write(ghostEnabled, .ghost) } }
    @Published var das: Double { didSet { write(das, .das) } }
    @Published var arr: Double { didSet { write(arr, .arr) } }
    @Published var onScreenButtons: Bool { didSet { write(onScreenButtons, .onScreenButtons) } }
    @Published var handedness: Handedness { didSet { write(handedness.rawValue, .handedness) } }
    @Published var musicEnabled: Bool { didSet { write(musicEnabled, .music) } }
    @Published var sfxEnabled: Bool { didSet { write(sfxEnabled, .sfx) } }
    @Published var hapticsEnabled: Bool { didSet { write(hapticsEnabled, .haptics) } }
    @Published var colorBlindMode: Bool { didSet { write(colorBlindMode, .colorBlind) } }

    /// DAS and ARR are exposed in milliseconds in the UI but stored in
    /// seconds, which is what the engine works in.
    static let dasRange: ClosedRange<Double> = 0.080...0.300
    static let arrRange: ClosedRange<Double> = 0.0...0.100

    private let defaults: UserDefaults

    private enum Key: String {
        case theme = "settings.theme"
        case ghost = "settings.ghost"
        case das = "settings.das"
        case arr = "settings.arr"
        case onScreenButtons = "settings.onScreenButtons"
        case handedness = "settings.handedness"
        case music = "settings.music"
        case sfx = "settings.sfx"
        case haptics = "settings.haptics"
        case colorBlind = "settings.colorBlind"
    }

    static let defaultDas = 0.133
    static let defaultArr = 0.033

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme.rawValue) ?? "") ?? .system
        ghostEnabled = defaults.object(forKey: Key.ghost.rawValue) as? Bool ?? true
        // Clamped on the way in: a value from an older build or a hand-edited
        // plist must not reach the engine, where a DAS of zero would slam the
        // piece into the wall on the lightest touch.
        das = SettingsStore.clamp(defaults.object(forKey: Key.das.rawValue) as? Double,
                                  to: SettingsStore.dasRange, fallback: SettingsStore.defaultDas)
        arr = SettingsStore.clamp(defaults.object(forKey: Key.arr.rawValue) as? Double,
                                  to: SettingsStore.arrRange, fallback: SettingsStore.defaultArr)
        onScreenButtons = defaults.object(forKey: Key.onScreenButtons.rawValue) as? Bool ?? false
        handedness = Handedness(rawValue: defaults.string(forKey: Key.handedness.rawValue) ?? "") ?? .right
        musicEnabled = defaults.object(forKey: Key.music.rawValue) as? Bool ?? true
        sfxEnabled = defaults.object(forKey: Key.sfx.rawValue) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics.rawValue) as? Bool ?? true
        colorBlindMode = defaults.object(forKey: Key.colorBlind.rawValue) as? Bool ?? false
    }

    var gameConfig: GameConfig {
        GameConfig(das: das, arr: arr, ghostEnabled: ghostEnabled, startLevel: 1)
    }

    private func write(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private static func clamp(_ value: Double?,
                              to range: ClosedRange<Double>,
                              fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
