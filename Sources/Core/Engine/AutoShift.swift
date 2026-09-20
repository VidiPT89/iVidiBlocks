import Foundation

/// Delayed Auto Shift: holding left or right nudges the piece once, waits out
/// the DAS charge, then repeats every ARR. Kept apart from the engine because
/// it is pure timing with no knowledge of the board, and because the feel of
/// a game lives or dies on these two numbers.
struct AutoShift {

    /// What the caller should do with the piece this frame.
    enum Shift: Equatable {
        case stay
        case step(Int)
        /// ARR of zero: slide until something stops it.
        case slam(Int)
    }

    var das: TimeInterval
    var arr: TimeInterval

    private(set) var direction = 0
    private var charged = false
    private var dasTimer: TimeInterval = 0
    private var arrTimer: TimeInterval = 0

    init(das: TimeInterval, arr: TimeInterval) {
        self.das = das
        self.arr = arr
    }

    /// Point the shift left (-1), right (1) or nowhere (0).
    /// - Returns: the immediate tap that a fresh press is owed.
    mutating func setDirection(_ raw: Int) -> Shift {
        let clamped = raw == 0 ? 0 : (raw > 0 ? 1 : -1)
        guard clamped != direction else { return .stay }

        direction = clamped
        dasTimer = 0
        arrTimer = 0
        charged = false
        return clamped == 0 ? .stay : .step(clamped)
    }

    mutating func release() {
        direction = 0
        charged = false
        dasTimer = 0
        arrTimer = 0
    }

    /// Re-arms the repeat for a newly spawned piece, so a held direction keeps
    /// sliding instead of making the player lift and press again.
    mutating func carryOverToNextPiece() {
        guard direction != 0, charged else { return }
        arrTimer = arr
    }

    mutating func tick(deltaTime: TimeInterval) -> Shift {
        guard direction != 0 else { return .stay }

        if !charged {
            dasTimer += deltaTime
            guard dasTimer >= das else { return .stay }
            charged = true
            arrTimer = 0
            return arr <= 0 ? .slam(direction) : .stay
        }

        guard arr > 0 else { return .slam(direction) }

        var steps = 0
        arrTimer += deltaTime
        while arrTimer >= arr {
            arrTimer -= arr
            steps += 1
        }
        return steps > 0 ? .step(direction * steps) : .stay
    }
}
