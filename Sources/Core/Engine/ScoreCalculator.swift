import Foundation

/// Everything that happened when a piece locked, used both for scoring and
/// for deciding which banner and effect to play.
struct ClearOutcome: Equatable {
    var lines: Int
    var spin: SpinKind
    var perfectClear: Bool
    var backToBack: Bool
    var combo: Int
    var points: Int

    /// Hard clears (a Tetris, or any T-spin that cleared lines) are what
    /// keeps a back-to-back chain alive.
    var isDifficult: Bool {
        if lines == 4 { return true }
        return spin != .none && lines > 0
    }

    var bannerKey: LocKey? {
        if perfectClear { return .gamePerfectClear }
        switch spin {
        case .full: return .gameTSpin
        case .mini: return .gameTSpinMini
        case .none: break
        }
        switch lines {
        case 4: return .gameTetris
        case 3: return .gameTriple
        case 2: return .gameDouble
        case 1: return .gameSingle
        default: return nil
        }
    }
}

enum ScoreCalculator {

    /// Base value of a clear before the level multiplier and B2B bonus.
    static func baseValue(lines: Int, spin: SpinKind, perfectClear: Bool) -> Int {
        if perfectClear {
            switch lines {
            case 1: return 800
            case 2: return 1200
            case 3: return 1800
            case 4: return 2000
            default: break
            }
        }

        switch spin {
        case .full:
            switch lines {
            case 0: return 400
            case 1: return 800
            case 2: return 1200
            case 3: return 1600
            default: return 0
            }
        case .mini:
            switch lines {
            case 0: return 100
            case 1: return 200
            default: return 0
            }
        case .none:
            switch lines {
            case 1: return 100
            case 2: return 300
            case 3: return 500
            case 4: return 800
            default: return 0
            }
        }
    }

    /// Full score for one locked piece, including the back-to-back
    /// multiplier and the combo bonus.
    static func points(lines: Int,
                       spin: SpinKind,
                       perfectClear: Bool,
                       level: Int,
                       backToBack: Bool,
                       combo: Int) -> Int {
        var total = Double(baseValue(lines: lines, spin: spin, perfectClear: perfectClear))
        if backToBack { total *= 1.5 }
        var points = Int(total) * max(level, 1)
        if combo > 0 && lines > 0 {
            points += 50 * combo * max(level, 1)
        }
        return points
    }

    static func softDropPoints(rows: Int) -> Int { rows }
    static func hardDropPoints(rows: Int) -> Int { rows * 2 }

    /// Seconds a piece takes to fall one row at a given level. Levels are
    /// capped at 20 so the game stays humanly playable.
    static func gravityInterval(level: Int) -> TimeInterval {
        let capped = min(max(level, 1), 20)
        let n = Double(capped - 1)
        return pow(0.8 - n * 0.007, n)
    }

    /// Marathon gains a level every ten lines.
    static func level(forTotalLines lines: Int, startingAt start: Int = 1) -> Int {
        start + lines / 10
    }
}
