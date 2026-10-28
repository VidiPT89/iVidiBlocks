import Foundation

/// The circular well: sixteen sectors around the circle and ten rings from
/// the rim to the core. Rings 0 and 1 are the hidden entry buffer outside
/// the rim, so the visible rings are 2...9, with 9 touching the core.
struct Board {
    static let sectors = 16
    static let rings = 10
    static let bufferRings = 2
    static let visibleRings = rings - bufferRings
    /// Same-colour cells in a row along a ring that fuse into an arc.
    static let arcLength = 5

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

    /// Any sector index, folded back onto the circle.
    static func wrap(_ x: Int) -> Int {
        ((x % sectors) + sectors) % sectors
    }

    subscript(x: Int, y: Int) -> ShardColor? {
        get {
            guard isInside(y: y) else { return nil }
            return cells[y * Board.sectors + Board.wrap(x)]
        }
        set {
            guard isInside(y: y) else { return }
            cells[y * Board.sectors + Board.wrap(x)] = newValue
        }
    }

    func isInside(y: Int) -> Bool {
        y >= 0 && y < Board.rings
    }

    /// True for a filled cell, for the core and for anything beyond the
    /// buffer. There are no side walls: the sectors wrap.
    func isBlocked(x: Int, y: Int) -> Bool {
        guard isInside(y: y) else { return true }
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

    /// Everything that would clear right now: full rings, plus every run of
    /// `arcLength` or more same-coloured cells along a ring.
    func scan() -> ClearScan {
        var scan = ClearScan()
        for y in Board.bufferRings..<Board.rings {
            if isRingFull(y) {
                scan.rings += 1
                for x in 0..<Board.sectors { scan.cells.insert(Point(x: x, y: y)) }
            }
            for run in sameColourRuns(inRing: y) where run.count >= Board.arcLength {
                scan.arcs += 1
                scan.cells.formUnion(run.map { Point(x: $0, y: y) })
            }
        }
        return scan
    }

    /// Runs of one colour along a ring, as sector lists, following the
    /// circle across sector 0. A ring entirely of one colour is one run.
    private func sameColourRuns(inRing y: Int) -> [[Int]] {
        let ring = (0..<Board.sectors).map { self[$0, y] }
        guard let start = (0..<Board.sectors).first(where: { ring[$0] != ring[Board.wrap($0 - 1)] }) else {
            return ring[0] == nil ? [] : [Array(0..<Board.sectors)]
        }
        var runs: [[Int]] = []
        var current: [Int] = []
        for step in 0..<Board.sectors {
            let x = Board.wrap(start + step)
            if let last = current.last, ring[x] != ring[last] {
                if ring[last] != nil { runs.append(current) }
                current = []
            }
            current.append(x)
        }
        if let last = current.last, ring[last] != nil { runs.append(current) }
        return runs
    }

    /// Removes the given cells. In each sector, whatever sat outside a
    /// removed cell slides inwards by one ring for every cell removed
    /// beneath it; gaps that were already there stay where they are.
    mutating func remove(_ doomed: Set<Point>) {
        guard !doomed.isEmpty else { return }
        var next = Board()
        for x in 0..<Board.sectors {
            var shift = 0
            for y in stride(from: Board.rings - 1, through: 0, by: -1) {
                if doomed.contains(Point(x: x, y: y)) {
                    shift += 1
                } else if let color = self[x, y] {
                    next[x, y + shift] = color
                }
            }
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
