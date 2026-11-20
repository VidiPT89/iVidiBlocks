import Foundation

/// Board coordinates: x grows rightwards and y grows downwards.
struct Point: Hashable, Codable {
    var x: Int
    var y: Int

    static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

/// Quarter turns of a shard, in clockwise order.
enum RotationState: Int, CaseIterable, Codable {
    case spawn = 0
    case right = 1
    case flipped = 2
    case left = 3

    var clockwise: RotationState { RotationState(rawValue: (rawValue + 1) % 4)! }
    var counterClockwise: RotationState { RotationState(rawValue: (rawValue + 3) % 4)! }
}

/// The seven four-cell pieces and their rotation boxes.
enum ShardShape: Int, CaseIterable, Codable {
    case i, o, t, s, z, j, l

    func cells(in state: RotationState) -> [Point] {
        let coordinates: [(Int, Int)]
        switch self {
        case .i: coordinates = [(0,1),(1,1),(2,1),(3,1)]
        case .o: coordinates = [(1,0),(2,0),(1,1),(2,1)]
        case .t: coordinates = [(1,0),(0,1),(1,1),(2,1)]
        case .s: coordinates = [(1,0),(2,0),(0,1),(1,1)]
        case .z: coordinates = [(0,0),(1,0),(1,1),(2,1)]
        case .j: coordinates = [(0,0),(0,1),(1,1),(2,1)]
        case .l: coordinates = [(2,0),(0,1),(1,1),(2,1)]
        }
        return coordinates.map { x, y in
            var point = Point(x: x, y: y)
            if self != .o {
                for _ in 0..<state.rawValue {
                    point = Point(x: (self == .i ? 3 : 2) - point.y, y: point.x)
                }
            }
            return point
        }
    }
}

/// Piece colours are visual identifiers; only complete rows clear.
enum ShardColor: Int, CaseIterable, Codable {
    case ember, amber, tide, violet, green, red, blue

    /// Name of the colour set in `Assets.xcassets`.
    var colorName: String {
        switch self {
        case .ember: return "PieceL"
        case .amber: return "PieceO"
        case .tide: return "PieceI"
        case .violet: return "PieceT"
        case .green: return "PieceS"
        case .red: return "PieceZ"
        case .blue: return "PieceJ"
        }
    }

    /// Distinct glyph drawn inside each cell in colour-blind mode, so the
    /// colours stay tellable apart without relying on hue.
    var accessibilityGlyph: String {
        switch self {
        case .ember: return "●"
        case .amber: return "▲"
        case .tide: return "■"
        case .violet: return "◆"
        case .green: return "+"
        case .red: return "×"
        case .blue: return "="
        }
    }
}

/// What the dealer hands out: an outline and a colour.
struct Shard: Hashable, Codable {
    var shape: ShardShape
    var color: ShardColor

    /// Every outline in every colour, the contents of one bag.
    static let all: [Shard] = zip(ShardShape.allCases,
        [ShardColor.tide, .amber, .violet, .green, .red, .blue, .ember])
        .map { Shard(shape: $0.0, color: $0.1) }

}

/// A shard in the well: what it is, how it is turned and where its pivot
/// sits. The origin's sector is always kept inside `0..<Board.sectors`.
struct Piece: Equatable, Codable {
    var shard: Shard
    var state: RotationState
    var origin: Point

    init(shard: Shard, state: RotationState = .spawn, origin: Point) {
        self.shard = shard
        self.state = state
        self.origin = Point(x: origin.x, y: origin.y)
    }

    var color: ShardColor { shard.color }

    /// Absolute board coordinates, without wrapping.
    var cells: [Point] {
        shard.shape.cells(in: state).map { offset in
            Point(x: origin.x + offset.x, y: origin.y + offset.y)
        }
    }

    /// Angular centre of the shard in sectors, unwrapped, so the renderer
    /// can turn the well to keep it at the top.
    var centreSector: Double {
        let offsets = shard.shape.cells(in: state).map { Double($0.x) }
        return Double(origin.x) + offsets.reduce(0, +) / Double(offsets.count)
    }

    func moved(dx: Int, dy: Int) -> Piece {
        var copy = self
        copy.origin = Point(x: origin.x + dx, y: origin.y + dy)
        return copy
    }

    func rotated(to state: RotationState) -> Piece {
        var copy = self
        copy.state = state
        return copy
    }
}
