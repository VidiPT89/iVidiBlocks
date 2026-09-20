import Foundation

/// Seedable generator so tests can replay an exact sequence of pieces.
protocol PieceRandomSource {
    mutating func shuffle(_ pieces: inout [TetrominoType])
}

struct SystemPieceRandom: PieceRandomSource {
    func shuffle(_ pieces: inout [TetrominoType]) {
        pieces.shuffle()
    }
}

/// Deterministic xorshift, used by the unit tests.
struct SeededPieceRandom: PieceRandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    private mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func shuffle(_ pieces: inout [TetrominoType]) {
        guard pieces.count > 1 else { return }
        for i in stride(from: pieces.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            pieces.swapAt(i, j)
        }
    }
}

/// The 7-bag randomiser: every group of seven contains each piece exactly
/// once, so no piece can drought and no piece can flood.
struct RandomBag {
    /// How many upcoming pieces the preview shows. The HUD draws exactly
    /// this many, so queueing more would only be waste.
    static let previewCount = 4

    private var queue: [TetrominoType] = []
    private var random: PieceRandomSource

    init(random: PieceRandomSource = SystemPieceRandom()) {
        self.random = random
        refillIfNeeded()
    }

    private mutating func refillIfNeeded() {
        // Keep two bags queued so the 5-piece preview is always full.
        while queue.count <= RandomBag.previewCount {
            var bag = TetrominoType.allCases
            random.shuffle(&bag)
            queue.append(contentsOf: bag)
        }
    }

    mutating func next() -> TetrominoType {
        refillIfNeeded()
        return queue.removeFirst()
    }

    /// The next pieces, without consuming them.
    var preview: [TetrominoType] {
        Array(queue.prefix(RandomBag.previewCount))
    }
}
