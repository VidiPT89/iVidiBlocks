import Foundation

/// The playfield grid. Rows 0 and 1 are the hidden spawn buffer, so the
/// visible area is rows 2...21. `y` grows downwards from the top.
struct Board {
    static let columns = 10
    static let rows = 22
    static let bufferRows = 2

    /// Row-major storage: `cells[y * columns + x]`, `nil` meaning empty.
    private(set) var cells: [TetrominoType?]

    init() {
        cells = Array(repeating: nil, count: Board.columns * Board.rows)
    }

    subscript(x: Int, y: Int) -> TetrominoType? {
        get {
            guard isInside(x: x, y: y) else { return nil }
            return cells[y * Board.columns + x]
        }
        set {
            guard isInside(x: x, y: y) else { return }
            cells[y * Board.columns + x] = newValue
        }
    }

    func isInside(x: Int, y: Int) -> Bool {
        x >= 0 && x < Board.columns && y >= 0 && y < Board.rows
    }

    /// True when the cell is out of bounds or already filled. Treating the
    /// walls and floor as solid is what makes the T-spin corner test work.
    func isBlocked(x: Int, y: Int) -> Bool {
        guard isInside(x: x, y: y) else { return true }
        return cells[y * Board.columns + x] != nil
    }

    func canPlace(_ piece: Piece) -> Bool {
        for cell in piece.cells where isBlocked(x: cell.x, y: cell.y) {
            return false
        }
        return true
    }

    mutating func lock(_ piece: Piece) {
        for cell in piece.cells {
            self[cell.x, cell.y] = piece.type
        }
    }

    /// Drops the piece as far as it will go without colliding.
    func hardDropPosition(of piece: Piece) -> Piece {
        var result = piece
        while canPlace(result.moved(dx: 0, dy: 1)) {
            result = result.moved(dx: 0, dy: 1)
        }
        return result
    }

    func isRowFull(_ y: Int) -> Bool {
        for x in 0..<Board.columns where self[x, y] == nil { return false }
        return true
    }

    func isEmpty() -> Bool {
        cells.allSatisfy { $0 == nil }
    }

    /// Indices of every complete row, top to bottom.
    func completedRows() -> [Int] {
        (0..<Board.rows).filter { isRowFull($0) }
    }

    /// Removes the given rows and collapses everything above them down.
    mutating func clearRows(_ rows: [Int]) {
        guard !rows.isEmpty else { return }
        let doomed = Set(rows)
        var surviving = [TetrominoType?]()
        surviving.reserveCapacity(cells.count)

        for y in 0..<Board.rows where !doomed.contains(y) {
            let start = y * Board.columns
            surviving.append(contentsOf: cells[start..<(start + Board.columns)])
        }

        let padding = Array<TetrominoType?>(repeating: nil,
                                            count: rows.count * Board.columns)
        cells = padding + surviving
    }

    /// Highest occupied row index, or `nil` when the board is empty.
    /// Used to drive the danger vignette.
    func highestOccupiedRow() -> Int? {
        for y in 0..<Board.rows {
            for x in 0..<Board.columns where self[x, y] != nil { return y }
        }
        return nil
    }
}
