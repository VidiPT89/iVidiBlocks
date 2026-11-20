import XCTest
@testable import iVidiBlocks

final class BoardTests: XCTestCase {
    func testDimensionsAndWalls() {
        let board = Board()
        XCTAssertEqual(Board.sectors, 10)
        XCTAssertEqual(Board.visibleRings, 20)
        for point in [Point(x: -1, y: 3), Point(x: 10, y: 3), Point(x: 0, y: 22)] {
            XCTAssertTrue(board.isBlocked(x: point.x, y: point.y))
        }
        XCTAssertFalse(board.isBlocked(x: 0, y: 2))
    }
    func testSevenTetrominoesAndFourRotations() {
        XCTAssertEqual(Shard.all.count, 7)
        for shape in ShardShape.allCases {
            for state in RotationState.allCases {
                XCTAssertEqual(Set(shape.cells(in: state)).count, 4)
            }
            let piece = Piece(shard: Shard.all.first { $0.shape == shape }!, origin: Point(x: 3, y: 5))
            var turned = piece
            for _ in 0..<4 { turned = RotationSystem.rotate(turned, clockwise: true, on: Board())?.piece ?? turned }
            XCTAssertEqual(Set(turned.cells), Set(piece.cells))
        }
    }
    func testColourGroupsDoNotClear() {
        var board = Board()
        for x in 0..<9 { board[x, 21] = .amber }
        XCTAssertTrue(board.scan().isEmpty)
        board[9, 21] = .tide
        XCTAssertEqual(board.scan().rings, 1)
        XCTAssertEqual(board.scan().arcs, 0)
    }
    func testWholeRowsFallTogetherIncludingGaps() {
        var board = Board()
        for y in [20, 21] { for x in 0..<10 { board[x,y] = .ember } }
        board[3,19] = .tide
        board[4,17] = .amber
        board.remove(board.scan().cells)
        XCTAssertEqual(board[3,21], .tide)
        XCTAssertEqual(board[4,19], .amber)
        XCTAssertNil(board[4,20])
    }
    func testRotationCannotPassThroughWallOrFloor() {
        let shard = Shard(shape: .i, color: .tide)
        let vertical = Piece(shard: shard, state: .right, origin: Point(x: -2, y: 5))
        XCTAssertTrue(Board().canPlace(vertical))
        XCTAssertNil(RotationSystem.rotate(vertical, clockwise: true, on: Board()))
        let horizontal = Piece(shard: shard, origin: Point(x: 3, y: 20))
        XCTAssertNil(RotationSystem.rotate(horizontal, clockwise: true, on: Board()))
    }
}
