import Foundation

enum SpinKind: Equatable {
    case none
    case mini
    case full
}

/// Three-corner T-spin detection. Only the T piece can spin, and only when
/// the very last action before the lock was a rotation.
enum SpinDetector {

    /// - Parameters:
    ///   - piece: the T piece in its final, locked position.
    ///   - kickIndex: which SRS offset the rotation landed on. Index 4
    ///     (the fifth test) always promotes a mini to a full T-spin.
    static func detect(piece: Piece,
                       lastActionWasRotation: Bool,
                       kickIndex: Int,
                       board: Board) -> SpinKind {
        guard piece.type == .t, lastActionWasRotation else { return .none }

        let corners = corners(of: piece)
        let occupied = corners.filter { board.isBlocked(x: $0.x, y: $0.y) }
        guard occupied.count >= 3 else { return .none }

        let front = frontCorners(of: piece)
        let occupiedFront = front.filter { board.isBlocked(x: $0.x, y: $0.y) }.count

        if occupiedFront >= 2 { return .full }
        // Landing on the last kick is always treated as a proper T-spin.
        return kickIndex == 4 ? .full : .mini
    }

    /// The four corners of the T piece's 3x3 rotation box.
    private static func corners(of piece: Piece) -> [Point] {
        let o = piece.origin
        return [
            Point(x: o.x, y: o.y),
            Point(x: o.x + 2, y: o.y),
            Point(x: o.x, y: o.y + 2),
            Point(x: o.x + 2, y: o.y + 2)
        ]
    }

    /// The two corners on the side the T is pointing towards.
    private static func frontCorners(of piece: Piece) -> [Point] {
        let o = piece.origin
        switch piece.state {
        case .spawn:                                    // pointing up
            return [Point(x: o.x, y: o.y), Point(x: o.x + 2, y: o.y)]
        case .right:                                    // pointing right
            return [Point(x: o.x + 2, y: o.y), Point(x: o.x + 2, y: o.y + 2)]
        case .flipped:                                  // pointing down
            return [Point(x: o.x, y: o.y + 2), Point(x: o.x + 2, y: o.y + 2)]
        case .left:                                     // pointing left
            return [Point(x: o.x, y: o.y), Point(x: o.x, y: o.y + 2)]
        }
    }
}
