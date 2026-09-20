import Foundation

/// The vocabulary the engine and its callers share: what goes in, what comes
/// out and what state a run can be in. Kept separate from `GameEngine` so the
/// renderer and the view model can be read without opening the rules.

/// Tunables the player can change in Settings. Passed in so the engine stays
/// free of any storage or UI dependency.
struct GameConfig {
    var das: TimeInterval = 0.133
    var arr: TimeInterval = 0.033
    var ghostEnabled: Bool = true
    var startLevel: Int = 1

    static let `default` = GameConfig()
}

/// Something worth reacting to, drained by the renderer once per frame.
enum GameEvent: Equatable {
    case spawned
    case moved
    case rotated(kicked: Bool)
    case rotationFailed
    case softDropped(rows: Int)
    /// Carries the landed piece because by the time the renderer drains this
    /// the engine has already locked it and cleared `current`.
    case hardDropped(rows: Int, from: Int, piece: Piece)
    case locked(piece: Piece)
    case linesCleared(rows: [Int], outcome: ClearOutcome)
    case levelUp(Int)
    case holdSwapped
    case holdRejected
    case gameOver(reason: GameOverReason)
}

extension GameOverReason: Equatable {}

enum GamePhase: Equatable {
    case ready
    case playing
    /// Gravity is frozen while completed rows play their clear animation.
    case clearing
    case paused
    case over(GameOverReason)
}

/// Accumulated counters for one run, folded into lifetime stats at the end.
struct RunStats {
    var piecesPlaced = 0
    var linesCleared = 0
    var tetrises = 0
    var tSpins = 0
    var maxCombo = 0
}
