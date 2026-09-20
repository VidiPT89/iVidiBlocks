import Foundation

/// Super Rotation System. On a failed rotation the piece is nudged through
/// up to four alternative offsets ("wall kicks") before the turn is refused.
enum RotationSystem {

    struct Result {
        var piece: Piece
        /// Index of the offset that succeeded, 0...4. Test 5 (index 4) is what
        /// promotes a T-spin mini to a full T-spin.
        var kickIndex: Int
    }

    /// Attempts a rotation, returning the kicked piece or `nil` if all five
    /// tests collide.
    static func rotate(_ piece: Piece,
                       clockwise: Bool,
                       on board: Board) -> Result? {
        guard piece.type != .o else { return nil }

        let target = clockwise ? piece.state.clockwise : piece.state.counterClockwise
        let table = piece.type == .i ? iKicks : standardKicks
        guard let offsets = table[Transition(from: piece.state, to: target)] else { return nil }

        for (index, offset) in offsets.enumerated() {
            // The published tables use y-up; the board is y-down, so flip y.
            let candidate = Piece(type: piece.type,
                                  state: target,
                                  origin: Point(x: piece.origin.x + offset.x,
                                                y: piece.origin.y - offset.y))
            if board.canPlace(candidate) {
                return Result(piece: candidate, kickIndex: index)
            }
        }
        return nil
    }

    private struct Transition: Hashable {
        let from: RotationState
        let to: RotationState
    }

    private typealias Offset = (x: Int, y: Int)

    private static let standardKicks: [Transition: [Offset]] = [
        Transition(from: .spawn, to: .right):     [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
        Transition(from: .right, to: .spawn):     [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
        Transition(from: .right, to: .flipped):   [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
        Transition(from: .flipped, to: .right):   [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
        Transition(from: .flipped, to: .left):    [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
        Transition(from: .left, to: .flipped):    [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
        Transition(from: .left, to: .spawn):      [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
        Transition(from: .spawn, to: .left):      [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)]
    ]

    private static let iKicks: [Transition: [Offset]] = [
        Transition(from: .spawn, to: .right):     [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
        Transition(from: .right, to: .spawn):     [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
        Transition(from: .right, to: .flipped):   [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
        Transition(from: .flipped, to: .right):   [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
        Transition(from: .flipped, to: .left):    [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
        Transition(from: .left, to: .flipped):    [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
        Transition(from: .left, to: .spawn):      [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
        Transition(from: .spawn, to: .left):      [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)]
    ]
}
