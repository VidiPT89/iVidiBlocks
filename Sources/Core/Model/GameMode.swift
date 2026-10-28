import Foundation

enum GameMode: String, CaseIterable, Identifiable, Codable {
    case orbit
    case target
    case blitz

    var id: String { rawValue }

    var titleKey: LocKey {
        switch self {
        case .orbit: return .modeOrbit
        case .target: return .modeTarget
        case .blitz: return .modeBlitz
        }
    }

    var descriptionKey: LocKey {
        switch self {
        case .orbit: return .modeOrbitDesc
        case .target: return .modeTargetDesc
        case .blitz: return .modeBlitzDesc
        }
    }

    var symbolName: String {
        switch self {
        case .orbit: return "circle.dashed"
        case .target: return "scope"
        case .blitz: return "timer"
        }
    }

    /// Cleared cells that end a Target run.
    var shardTarget: Int? { self == .target ? 160 : nil }

    /// Seconds on the clock for a timed mode.
    var timeLimit: TimeInterval? { self == .blitz ? 120 : nil }

    /// Orbit speeds up as it goes; the other modes stay at level 1 so runs
    /// are comparable between attempts.
    var levelsUp: Bool { self == .orbit }

    /// How a record is ranked, which decides both sorting and formatting.
    var scoring: ScoringKind {
        switch self {
        case .orbit, .blitz: return .highestScore
        case .target: return .fastestTime
        }
    }

    enum ScoringKind {
        case highestScore
        case fastestTime
    }
}

/// Why a run ended, so the result screen can say the right thing.
enum GameOverReason {
    /// A shard could not enter the well.
    case topOut
    /// A Target run cleared its quota.
    case targetReached
    /// A Blitz run ran out of clock.
    case timeUp
}
