import Foundation

/// Everything one clearing step removed, used both for scoring and for
/// deciding which banner and effect to play.
struct ClearOutcome: Equatable {
    var cells: Int
    var rings: Int
    var arcs: Int
    /// 1 for the clear a lock caused directly, 2 for the cascade it set off
    /// once the outer cells slid inwards, and so on.
    var chain: Int
    var points: Int

    var bannerKey: LocKey? {
        if chain > 1 { return .gameChain }
        if rings > 1 { return .gameRings }
        if rings == 1 { return .gameRing }
        if arcs > 0 { return .gameArc }
        return nil
    }
}

enum ScoreCalculator {

    static let pointsPerCell = 10
    static let pointsPerRing = 100
    static let pointsPerArc = 60
    static let pointsPerPulsedCell = 5

    /// Score for one clearing step. Every link of a chain multiplies the
    /// whole step, which is what makes setting up cascades worth the risk.
    static func points(cells: Int, rings: Int, arcs: Int, chain: Int, level: Int) -> Int {
        let base = cells * pointsPerCell + rings * pointsPerRing + arcs * pointsPerArc
        return base * max(chain, 1) * max(level, 1)
    }

    /// A pulse pays a little for what it removes, so it rescues a run
    /// rather than farming points.
    static func pulsePoints(cells: Int, level: Int) -> Int {
        cells * pointsPerPulsedCell * max(level, 1)
    }

    static func softDropPoints(rings: Int) -> Int { rings }
    static func hardDropPoints(rings: Int) -> Int { rings * 2 }

    /// Seconds a shard takes to fall one ring at a given level. Levels are
    /// capped at 20 so the game stays humanly playable.
    static func gravityInterval(level: Int) -> TimeInterval {
        let capped = min(max(level, 1), 20)
        let n = Double(capped - 1)
        return 0.9 * pow(0.8 - n * 0.007, n)
    }

    /// Cleared cells needed for each level in Orbit.
    static let shardsPerLevel = 48

    static func level(forTotalShards shards: Int, startingAt start: Int = 1) -> Int {
        start + shards / shardsPerLevel
    }
}
