import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case pt
    case en

    var id: String { rawValue }

    /// Matches the `.lproj` folder shipped in Resources.
    var lprojName: String {
        switch self {
        case .pt: return "pt-PT"
        case .en: return "en"
        }
    }

    var displayName: String {
        switch self {
        case .pt: return "Português"
        case .en: return "English"
        }
    }

    var shortName: String {
        switch self {
        case .pt: return "PT"
        case .en: return "EN"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .pt ? "pt_PT" : "en_US")
    }

    /// Best match for the device language, used the very first time the app
    /// is opened and never again.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("pt") ? .pt : .en
    }
}

/// Every user-visible string in the app. Raw values match the keys in
/// `Localizable.strings`, so nothing is ever written literally in a view.
enum LocKey: String, CaseIterable {
    case appName = "app.name"
    case appTagline = "app.tagline"

    case splashDevelopedBy = "splash.developedBy"
    case splashSkip = "splash.skip"

    case menuSettings = "menu.settings"
    case menuStats = "menu.stats"
    case menuHowTo = "menu.howto"
    case menuAbout = "menu.about"
    case menuBest = "menu.best"
    case menuNoRecord = "menu.noRecord"

    case modeMarathon = "mode.marathon"
    case modeMarathonDesc = "mode.marathon.desc"
    case modeSprint = "mode.sprint"
    case modeSprintDesc = "mode.sprint.desc"
    case modeUltra = "mode.ultra"
    case modeUltraDesc = "mode.ultra.desc"

    case hudScore = "hud.score"
    case hudLevel = "hud.level"
    case hudLines = "hud.lines"
    case hudTime = "hud.time"
    case hudHold = "hud.hold"
    case hudNext = "hud.next"
    case hudCombo = "hud.combo"
    case hudBackToBack = "hud.b2b"

    case gameSingle = "game.single"
    case gameDouble = "game.double"
    case gameTriple = "game.triple"
    case gameTetris = "game.tetris"
    case gameTSpin = "game.tspin"
    case gameTSpinMini = "game.tspinMini"
    case gamePerfectClear = "game.perfectClear"
    case gameLevelUp = "game.levelUp"
    case gameReady = "game.ready"

    case pauseTitle = "pause.title"
    case pauseResume = "pause.resume"
    case pauseRestart = "pause.restart"
    case pauseQuit = "pause.quit"

    case gameOverTitle = "gameover.title"
    case gameOverComplete = "gameover.complete"
    case gameOverTimeUp = "gameover.timeUp"
    case gameOverNewRecord = "gameover.newRecord"
    case gameOverPlayAgain = "gameover.playAgain"
    case gameOverMenu = "gameover.menu"

    case settingsTitle = "settings.title"
    case settingsLanguage = "settings.language"
    case settingsTheme = "settings.theme"
    case settingsThemeSystem = "settings.theme.system"
    case settingsThemeLight = "settings.theme.light"
    case settingsThemeDark = "settings.theme.dark"
    case settingsGameplay = "settings.gameplay"
    case settingsGhost = "settings.ghost"
    case settingsDAS = "settings.das"
    case settingsARR = "settings.arr"
    case settingsControls = "settings.controls"
    case settingsOnScreenButtons = "settings.onScreenButtons"
    case settingsHandedness = "settings.handedness"
    case settingsHandednessLeft = "settings.handedness.left"
    case settingsHandednessRight = "settings.handedness.right"
    case settingsAudio = "settings.audio"
    case settingsMusic = "settings.music"
    case settingsSFX = "settings.sfx"
    case settingsHaptics = "settings.haptics"
    case settingsAccessibility = "settings.accessibility"
    case settingsColorBlind = "settings.colorBlind"
    case settingsDone = "settings.done"
    case settingsResetStats = "settings.resetStats"
    case settingsResetStatsConfirm = "settings.resetStats.confirm"
    case settingsCancel = "settings.cancel"
    case settingsReset = "settings.reset"

    case statsTitle = "stats.title"
    case statsRecords = "stats.records"
    case statsLifetime = "stats.lifetime"
    case statsGames = "stats.games"
    case statsPieces = "stats.pieces"
    case statsLines = "stats.lines"
    case statsTetrises = "stats.tetrises"
    case statsTSpins = "stats.tspins"
    case statsTimePlayed = "stats.timePlayed"
    case statsBestCombo = "stats.bestCombo"
    case statsEmpty = "stats.empty"

    case howToTitle = "howto.title"
    case howToGoal = "howto.goal"
    case howToGoalBody = "howto.goal.body"
    case howToControls = "howto.controls"
    case howToControlsMove = "howto.controls.move"
    case howToControlsRotate = "howto.controls.rotate"
    case howToControlsSoft = "howto.controls.soft"
    case howToControlsHard = "howto.controls.hard"
    case howToControlsHold = "howto.controls.hold"
    case howToScoring = "howto.scoring"
    case howToScoringBody = "howto.scoring.body"
    case howToTips = "howto.tips"
    case howToTipsBody = "howto.tips.body"

    case controlsLeft = "controls.left"
    case controlsRight = "controls.right"
    case controlsRotateCW = "controls.rotateCW"
    case controlsRotateCCW = "controls.rotateCCW"
    case controlsSoftDrop = "controls.softDrop"
    case controlsHardDrop = "controls.hardDrop"
    case controlsHold = "controls.hold"

    case commonClose = "common.close"
}

/// Reads strings straight out of the bundled `.lproj` folders rather than
/// going through `Bundle.main`, so the in-app language switch takes effect
/// instantly and does not follow the device language.
final class LocalizationManager: ObservableObject {
    private static let storageKey = "settings.language"

    @Published private(set) var language: AppLanguage

    private var bundle: Bundle
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey)
        let resolved = stored.flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        self.language = resolved
        self.bundle = Self.bundle(for: resolved)
    }

    func setLanguage(_ language: AppLanguage) {
        // Stored even when it changes nothing on screen: picking the language
        // the device already uses is still a choice, and it has to outlive a
        // later change of the device language.
        defaults.set(language.rawValue, forKey: Self.storageKey)
        guard language != self.language else { return }
        self.language = language
        bundle = Self.bundle(for: language)
    }

    func string(_ key: LocKey) -> String {
        bundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: "Localizable")
    }

    private static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.lprojName, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
