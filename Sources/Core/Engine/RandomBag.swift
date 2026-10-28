import Foundation

/// Seedable generator so tests can replay an exact sequence of shards.
protocol PieceRandomSource {
    mutating func shuffle(_ shards: inout [Shard])
}

struct SystemPieceRandom: PieceRandomSource {
    func shuffle(_ shards: inout [Shard]) {
        shards.shuffle()
    }
}

/// Deals shards in bags of twelve, every outline in every colour once, so
/// no colour can go missing long enough to make arcs impossible.
struct RandomBag {
    /// How many upcoming shards the preview shows. The HUD draws exactly
    /// this many, so queueing more would only be waste.
    static let previewCount = 4

    private(set) var queue: [Shard] = []
    private var random: PieceRandomSource

    /// - Parameter queue: shards already dealt, kept when a saved run is
    ///   restored so the preview the player saw is still what comes next.
    init(queue: [Shard] = [], random: PieceRandomSource = SystemPieceRandom()) {
        self.queue = queue
        self.random = random
        refillIfNeeded()
    }

    private mutating func refillIfNeeded() {
        // Refill before consuming so the preview always stays full.
        while queue.count <= RandomBag.previewCount {
            var bag = Shard.all
            random.shuffle(&bag)
            queue.append(contentsOf: bag)
        }
    }

    mutating func next() -> Shard {
        refillIfNeeded()
        return queue.removeFirst()
    }

    /// The next shards, without consuming them.
    var preview: [Shard] {
        Array(queue.prefix(RandomBag.previewCount))
    }
}
