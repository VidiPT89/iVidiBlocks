import Foundation

/// A cell coordinate on the board. `x` grows right, `y` grows **down**.
struct Point: Hashable {
    var x: Int
    var y: Int

    static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

/// The four SRS rotation states, in clockwise order.
enum RotationState: Int, CaseIterable {
    case spawn = 0
    case right = 1
    case flipped = 2
    case left = 3

    var clockwise: RotationState { RotationState(rawValue: (rawValue + 1) % 4)! }
    var counterClockwise: RotationState { RotationState(rawValue: (rawValue + 3) % 4)! }
}

enum TetrominoType: Int, CaseIterable, Codable {
    case i, o, t, s, z, j, l

    /// Name of the colour set in `Assets.xcassets` for this piece.
    var colorName: String {
        switch self {
        case .i: return "PieceI"
        case .o: return "PieceO"
        case .t: return "PieceT"
        case .s: return "PieceS"
        case .z: return "PieceZ"
        case .j: return "PieceJ"
        case .l: return "PieceL"
        }
    }

    /// Distinct glyph drawn inside each block when colour-blind mode is on,
    /// so pieces stay tellable apart without relying on hue.
    var accessibilityGlyph: String {
        switch self {
        case .i: return "="
        case .o: return "□"
        case .t: return "T"
        case .s: return "S"
        case .z: return "Z"
        case .j: return "J"
        case .l: return "L"
        }
    }

    /// Width of the square rotation box: 4 for I, 2 for O, 3 for the rest.
    /// Only used for centring previews; SRS offsets live in `RotationSystem`.
    var boxSize: Int {
        switch self {
        case .i: return 4
        case .o: return 2
        default: return 3
        }
    }

    /// Cells occupied in each rotation state, relative to the piece origin.
    /// These are the canonical SRS shapes with `y` pointing down.
    func cells(in state: RotationState) -> [Point] {
        Self.shapes[self]![state.rawValue]
    }

    private static let shapes: [TetrominoType: [[Point]]] = [
        .i: [
            [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 3, y: 1)],
            [Point(x: 2, y: 0), Point(x: 2, y: 1), Point(x: 2, y: 2), Point(x: 2, y: 3)],
            [Point(x: 0, y: 2), Point(x: 1, y: 2), Point(x: 2, y: 2), Point(x: 3, y: 2)],
            [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 1, y: 2), Point(x: 1, y: 3)]
        ],
        .o: [
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)],
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)],
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)],
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)]
        ],
        .t: [
            [Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1)],
            [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 1, y: 2)],
            [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 1, y: 2)],
            [Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 1, y: 2)]
        ],
        .s: [
            [Point(x: 1, y: 0), Point(x: 2, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1)],
            [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 2, y: 2)],
            [Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 0, y: 2), Point(x: 1, y: 2)],
            [Point(x: 0, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 1, y: 2)]
        ],
        .z: [
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 1)],
            [Point(x: 2, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 1, y: 2)],
            [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 1, y: 2), Point(x: 2, y: 2)],
            [Point(x: 1, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 0, y: 2)]
        ],
        .j: [
            [Point(x: 0, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1)],
            [Point(x: 1, y: 0), Point(x: 2, y: 0), Point(x: 1, y: 1), Point(x: 1, y: 2)],
            [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 2, y: 2)],
            [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 2), Point(x: 1, y: 2)]
        ],
        .l: [
            [Point(x: 2, y: 0), Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1)],
            [Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 1, y: 2), Point(x: 2, y: 2)],
            [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 2, y: 1), Point(x: 0, y: 2)],
            [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 1, y: 2)]
        ]
    ]
}

/// A tetromino placed on the board: a type, a rotation and an origin.
struct Piece {
    var type: TetrominoType
    var state: RotationState
    var origin: Point

    init(type: TetrominoType, state: RotationState = .spawn, origin: Point) {
        self.type = type
        self.state = state
        self.origin = origin
    }

    /// Absolute board coordinates of the four blocks.
    var cells: [Point] {
        type.cells(in: state).map { $0 + origin }
    }

    func cells(in state: RotationState) -> [Point] {
        type.cells(in: state).map { $0 + origin }
    }

    func moved(dx: Int, dy: Int) -> Piece {
        var copy = self
        copy.origin = Point(x: origin.x + dx, y: origin.y + dy)
        return copy
    }
}
