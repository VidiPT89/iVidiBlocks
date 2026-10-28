import XCTest
@testable import iVidiBlocks

final class RandomBagTests: XCTestCase {

    func testEveryBagContainsEachShapeInEachColourExactlyOnce() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 42))
        for bagIndex in 0..<100 {
            let drawn = (0..<Shard.all.count).map { _ in bag.next() }
            XCTAssertEqual(Set(drawn), Set(Shard.all), "bag \(bagIndex) repeated a shard")
        }
    }

    func testNoColourGoesMissingForLong() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 99))
        var lastSeen: [ShardColor: Int] = [:]
        for index in 0..<6000 {
            let color = bag.next().color
            if let previous = lastSeen[color] {
                // Four of a colour per bag of twelve: at worst the last one
                // of a bag is followed by the first of the next after eight.
                XCTAssertLessThanOrEqual(index - previous - 1, 16)
            }
            lastSeen[color] = index
        }
    }

    func testPreviewDoesNotConsumeThePiecesItShows() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 1))
        let preview = bag.preview
        XCTAssertEqual(preview.count, RandomBag.previewCount)
        XCTAssertEqual(bag.preview, preview, "reading the preview must not consume")

        for expected in preview {
            XCTAssertEqual(bag.next(), expected)
        }
    }

    func testSameSeedProducesSameSequence() {
        var a = RandomBag(random: SeededPieceRandom(seed: 2024))
        var b = RandomBag(random: SeededPieceRandom(seed: 2024))
        let left = (0..<50).map { _ in a.next() }
        let right = (0..<50).map { _ in b.next() }
        XCTAssertEqual(left, right)
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

    mutating func shuffle(_ pieces: inout [Shard]) {
        guard pieces.count > 1 else { return }
        for i in stride(from: pieces.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            pieces.swapAt(i, j)
        }
    }
}
