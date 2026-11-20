import Foundation

/// Rectangular playfield: 10 columns, 20 visible rows and two spawn rows.
/// Historical storage names (sectors/rings) mean columns/rows.
struct Board {
    static let sectors = 10
    static let rings = 22
    static let bufferRings = 2
    static let visibleRings = rings - bufferRings
    /// Ring-major storage: `cells[y * sectors + x]`, `nil` meaning empty.
    private(set) var cells: [ShardColor?]

    init() {
        cells = Array(repeating: nil, count: Board.sectors * Board.rings)
    }

    /// Rebuilds a saved well, refusing storage of the wrong size.
    init?(cells: [ShardColor?]) {
        guard cells.count == Board.sectors * Board.rings else { return nil }
        self.cells = cells
    }

    subscript(x: Int, y: Int) -> ShardColor? {
        get {
            guard (0..<Board.sectors).contains(x), isInside(y: y) else { return nil }
            return cells[y * Board.sectors + x]
        }
        set {
            guard (0..<Board.sectors).contains(x), isInside(y: y) else { return }
            cells[y * Board.sectors + x] = newValue
        }
    }

    func isInside(y: Int) -> Bool {
        y >= 0 && y < Board.rings
    }

    /// Side walls, floor, space above the buffer and occupied cells block movement.
    func isBlocked(x: Int, y: Int) -> Bool {
        guard (0..<Board.sectors).contains(x), isInside(y: y) else { return true }
        return self[x, y] != nil
    }

    func canPlace(_ piece: Piece) -> Bool {
        piece.cells.allSatisfy { !isBlocked(x: $0.x, y: $0.y) }
    }

    mutating func lock(_ piece: Piece) {
        for cell in piece.cells {
            self[cell.x, cell.y] = piece.color
        }
    }

    /// Sends the piece as far towards the core as it will go.
    func dropPosition(of piece: Piece) -> Piece {
        var result = piece
        while canPlace(result.moved(dx: 0, dy: 1)) {
            result = result.moved(dx: 0, dy: 1)
        }
        return result
    }

    func isRingFull(_ y: Int) -> Bool {
        (0..<Board.sectors).allSatisfy { self[$0, y] != nil }
    }

    func isEmpty() -> Bool {
        cells.allSatisfy { $0 == nil }
    }

    /// Find every complete visible row, regardless of colour.
    func scan() -> ClearScan {
        var scan = ClearScan()
        for y in Board.bufferRings..<Board.rings {
            if isRingFull(y) {
                scan.rings += 1
                for x in 0..<Board.sectors { scan.cells.insert(Point(x: x, y: y)) }
            }

        }
        return scan
    }

    /// Remove complete rows and shift whole rows down, preserving holes.
    mutating func remove(_ doomed: Set<Point>) {
        let rows = Set(doomed.map(\.y)).filter { y in
            (0..<Board.sectors).allSatisfy { doomed.contains(Point(x: $0, y: y)) }
        }
        guard !rows.isEmpty else { return }
        var next = Board()
        var destination = Board.rings - 1
        for y in stride(from: Board.rings - 1, through: 0, by: -1) where !rows.contains(y) {
            for x in 0..<Board.sectors { next[x, destination] = self[x, y] }
            destination -= 1
        }
        self = next
    }

    /// Outermost occupied ring, or `nil` when the well is empty. Drives the
    /// danger vignette.
    func outermostOccupiedRing() -> Int? {
        (0..<Board.rings).first { y in (0..<Board.sectors).contains { self[$0, y] != nil } }
    }
}

/// The cells a lock or a cascade would clear, and why.
struct ClearScan: Equatable {
    var cells: Set<Point> = []
    var rings = 0
    var arcs = 0

    var isEmpty: Bool { cells.isEmpty }
}
