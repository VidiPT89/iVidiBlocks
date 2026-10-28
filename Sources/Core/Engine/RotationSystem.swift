import Foundation

/// Turns a shard a quarter turn. When the turned shard collides, it is
/// nudged one sector either way, then one ring outwards, before the turn is
/// refused. With no side walls there is never a wall to kick off, only
/// neighbouring cells and the core.
enum RotationSystem {

    struct Result {
        var piece: Piece
        /// Index of the offset that succeeded; 0 means no nudge was needed.
        var kickIndex: Int
    }

    /// Nudges tried in order, as (sectors, rings) with rings growing inwards.
    static let kicks: [Point] = [
        Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: -1, y: 0), Point(x: 0, y: -1)
    ]

    static func rotate(_ piece: Piece, clockwise: Bool, on board: Board) -> Result? {
        guard piece.shard.shape != .spark else { return nil }
        let target = clockwise ? piece.state.clockwise : piece.state.counterClockwise
        let turned = piece.rotated(to: target)
        for (index, kick) in kicks.enumerated() {
            let candidate = turned.moved(dx: kick.x, dy: kick.y)
            if board.canPlace(candidate) {
                return Result(piece: candidate, kickIndex: index)
            }
        }
        return nil
    }
}
