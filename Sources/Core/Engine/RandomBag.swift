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

/// The 7-bag randomiser: every group of seven contains each piece exactly
/// once, so no piece can drought and no piece can flood.
struct RandomBag {
    /// How many upcoming pieces the preview shows. The HUD draws exactly
    /// this many, so queueing more would only be waste.
    static let previewCount = 4

    private(set) var queue: [TetrominoType] = []
    private var random: PieceRandomSource

    /// - Parameter queue: pieces already dealt, kept when a saved run is
    ///   restored so the preview the player saw is still what comes next.
    init(queue: [TetrominoType] = [], random: PieceRandomSource = SystemPieceRandom()) {
        self.queue = queue
        self.random = random
        refillIfNeeded()
    }

    private mutating func refillIfNeeded() {
        // Refill before consuming so the preview always stays full.
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
