import Foundation

/// A cell coordinate in the well. `x` is the sector, counted clockwise from
/// the top and wrapping around the circle. `y` is the depth, growing
/// **inwards** from the rim towards the core.
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

/// The four shard outlines. None is larger than three cells, so a ring is
/// always filled by many small decisions rather than one lucky long piece.
enum ShardShape: Int, CaseIterable, Codable {
    case spark, duo, trio, bend

    /// Cells in the spawn state, around a pivot at (0, 0).
    private var baseCells: [Point] {
        switch self {
        case .spark: return [Point(x: 0, y: 0)]
        case .duo: return [Point(x: 0, y: 0), Point(x: 1, y: 0)]
        case .trio: return [Point(x: -1, y: 0), Point(x: 0, y: 0), Point(x: 1, y: 0)]
        case .bend: return [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1)]
        }
    }

    /// Cells relative to the pivot after the given number of clockwise
    /// quarter turns. With `y` pointing inwards, a clockwise turn maps
    /// (x, y) to (-y, x).
    func cells(in state: RotationState) -> [Point] {
        baseCells.map { cell in
            var point = cell
            for _ in 0..<state.rawValue { point = Point(x: -point.y, y: point.x) }
            return point
        }
    }
}

/// The three shard colours. Five of one colour side by side in a ring fuse
/// into an arc and clear, even when the ring itself is not full.
enum ShardColor: Int, CaseIterable, Codable {
    case ember, amber, tide

    /// Name of the colour set in `Assets.xcassets`.
    var colorName: String {
        switch self {
        case .ember: return "PieceL"
        case .amber: return "PieceO"
        case .tide: return "PieceI"
        }
    }

    /// Distinct glyph drawn inside each cell in colour-blind mode, so the
    /// colours stay tellable apart without relying on hue.
    var accessibilityGlyph: String {
        switch self {
        case .ember: return "●"
        case .amber: return "▲"
        case .tide: return "■"
        }
    }
}

/// What the dealer hands out: an outline and a colour.
struct Shard: Hashable, Codable {
    var shape: ShardShape
    var color: ShardColor

    /// Every outline in every colour, the contents of one bag.
    static let all: [Shard] = ShardShape.allCases.flatMap { shape in
        ShardColor.allCases.map { Shard(shape: shape, color: $0) }
    }
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
        self.origin = Point(x: Board.wrap(origin.x), y: origin.y)
    }

    var color: ShardColor { shard.color }

    /// Absolute well coordinates, with sectors wrapped around the circle.
    var cells: [Point] {
        shard.shape.cells(in: state).map { offset in
            Point(x: Board.wrap(origin.x + offset.x), y: origin.y + offset.y)
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
        copy.origin = Point(x: Board.wrap(origin.x + dx), y: origin.y + dy)
        return copy
    }

    func rotated(to state: RotationState) -> Piece {
        var copy = self
        copy.state = state
        return copy
    }
}
