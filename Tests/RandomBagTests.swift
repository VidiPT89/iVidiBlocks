import XCTest
@testable import iTetris

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

    func testPreviewShowsFivePiecesWithoutConsumingThem() {
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
