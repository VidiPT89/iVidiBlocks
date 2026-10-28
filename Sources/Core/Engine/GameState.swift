import Foundation

/// The vocabulary the engine and its callers share: what goes in, what comes
/// out and what state a run can be in. Kept separate from `GameEngine` so the
/// renderer and the view model can be read without opening the rules.

/// Tunables the player can change in Settings. Passed in so the engine stays
/// free of any storage or UI dependency.
struct GameConfig {
    var das: TimeInterval = 0.133
    var arr: TimeInterval = 0.05
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
    case softDropped(rings: Int)
    /// Carries the landed piece because by the time the renderer drains this
    /// the engine has already locked it and cleared `current`.
    case hardDropped(rings: Int, from: Int, piece: Piece)
    case locked(piece: Piece)
    /// Cells about to clear, with their colours, so the renderer can burst
    /// them before the board changes underneath.
    case cleared(cells: [Point], colors: [ShardColor], outcome: ClearOutcome)
    case levelUp(Int)
    case coreCharged
    case pulsed(cells: [Point], points: Int)
    case pulseRejected
    case gameOver(reason: GameOverReason)
}

extension GameOverReason: Equatable {}

enum GamePhase: Equatable {
    case ready
    case playing
    /// Gravity is frozen while cleared cells play their animation.
    case clearing
    case paused
    case over(GameOverReason)
}

/// Accumulated counters for one run, folded into lifetime stats at the end.
struct RunStats: Codable, Equatable {
    var piecesPlaced = 0
    var shardsCleared = 0
    var ringsCleared = 0
    var arcsFused = 0
    var pulses = 0
    var maxChain = 0
}

/// Everything needed to put an unfinished run back where it was left, so
/// leaving the app or quitting to the menu never costs a game in progress.
/// Player preferences such as DAS, ARR and the ghost are not part of it:
/// a resumed run picks up whatever Settings say now.
struct GameSnapshot: Codable, Equatable {
    /// Bumped whenever the layout changes. A file written by another version
    /// is discarded rather than half-read into the engine.
    static let currentVersion = 2

    var version = GameSnapshot.currentVersion
    var mode: GameMode
    var startLevel: Int
    var cells: [ShardColor?]
    /// `nil` only while cleared cells are waiting for their animation.
    var current: Piece?
    /// The sector at the top of the well, for when there is no piece.
    var aim: Int
    var queue: [Shard]
    var pendingClear: [Point]
    var chain: Int
    var charge: Int
    var score: Int
    var shards: Int
    var level: Int
    var elapsed: TimeInterval
    var stats: RunStats
    var lockResets: Int
    var lowestRingReached: Int
}
