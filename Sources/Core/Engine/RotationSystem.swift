import Foundation

/// Classic rotation: reject collisions, without wall kicks or floor kicks.
enum RotationSystem {

    struct Result {
        var piece: Piece
        /// Index of the offset that succeeded; 0 means no nudge was needed.
        var kickIndex: Int
    }

    /// Nudges tried in order, as (sectors, rings) with rings growing inwards.
    static let kicks: [Point] = [
        Point(x: 0, y: 0)
    ]

    static func rotate(_ piece: Piece, clockwise: Bool, on board: Board) -> Result? {
        guard piece.shard.shape != .o else { return nil }
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
