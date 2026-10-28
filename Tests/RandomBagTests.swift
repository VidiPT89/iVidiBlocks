import XCTest
@testable import iVidiBlocks

final class RandomBagTests: XCTestCase {

    func testEveryBagOfSevenContainsEachPieceExactlyOnce() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 42))
        for bagIndex in 0..<100 {
            let drawn = (0..<7).map { _ in bag.next() }
            XCTAssertEqual(Set(drawn).count, 7, "bag \(bagIndex) repeated a piece")
        }
    }

    func testDistributionIsUniformOverManyDraws() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 7))
        var counts: [TetrominoType: Int] = [:]
        for _ in 0..<7000 { counts[bag.next(), default: 0] += 1 }

        XCTAssertEqual(counts.count, 7)
        for type in TetrominoType.allCases {
            XCTAssertEqual(counts[type], 1000, "\(type) should appear exactly once per bag")
        }
    }

    func testGapBetweenIdenticalPiecesNeverExceedsTwelve() {
        var bag = RandomBag(random: SeededPieceRandom(seed: 99))
        var lastSeen: [TetrominoType: Int] = [:]
        for index in 0..<7000 {
            let piece = bag.next()
            if let previous = lastSeen[piece] {
                XCTAssertLessThanOrEqual(index - previous - 1, 12,
                                         "drought of \(index - previous - 1) for \(piece)")
            }
            lastSeen[piece] = index
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

    mutating func shuffle(_ pieces: inout [TetrominoType]) {
        guard pieces.count > 1 else { return }
        for i in stride(from: pieces.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            pieces.swapAt(i, j)
        }
    }
}
