import Foundation

enum GameMode: String, CaseIterable, Identifiable, Codable {
    case marathon
    case sprint
    case ultra

    var id: String { rawValue }

    var titleKey: LocKey {
        switch self {
        case .marathon: return .modeMarathon
        case .sprint: return .modeSprint
        case .ultra: return .modeUltra
        }
    }

    var descriptionKey: LocKey {
        switch self {
        case .marathon: return .modeMarathonDesc
        case .sprint: return .modeSprintDesc
        case .ultra: return .modeUltraDesc
        }
    }

    var symbolName: String {
        switch self {
        case .marathon: return "infinity"
        case .sprint: return "bolt.fill"
        case .ultra: return "timer"
        }
    }

    /// Lines that end a Sprint run.
    var lineTarget: Int? { self == .sprint ? 40 : nil }

    /// Seconds on the clock for a timed mode.
    var timeLimit: TimeInterval? { self == .ultra ? 180 : nil }

    /// Marathon speeds up every 10 lines; the other modes stay at level 1
    /// so runs are comparable between attempts.
    var levelsUp: Bool { self == .marathon }

    /// How a record is ranked, which decides both sorting and formatting.
    var scoring: ScoringKind {
        switch self {
        case .marathon, .ultra: return .highestScore
        case .sprint: return .fastestTime
        }
    }

    enum ScoringKind {
        case highestScore
        case fastestTime
    }
}

/// Why a run ended, so the result screen can say the right thing.
enum GameOverReason {
    /// The stack reached the top.
    case topOut
    /// A Sprint run hit its line target.
    case targetReached
    /// An Ultra run ran out of clock.
    case timeUp
}
