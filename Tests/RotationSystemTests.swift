import XCTest
@testable import iTetris

final class RotationSystemTests: XCTestCase {

    /// Roomy spot in the middle of an empty board where no kick is needed.
    private let openOrigin = Point(x: 4, y: 10)

    func testOPieceNeverRotates() {
        let board = Board()
        let piece = Piece(type: .o, origin: openOrigin)
        XCTAssertNil(RotationSystem.rotate(piece, clockwise: true, on: board))
        XCTAssertNil(RotationSystem.rotate(piece, clockwise: false, on: board))
    }

    func testRotationInOpenSpaceUsesTheFirstTest() {
        let board = Board()
        for type in TetrominoType.allCases where type != .o {
            var piece = Piece(type: type, origin: openOrigin)
            for _ in 0..<4 {
                guard let result = RotationSystem.rotate(piece, clockwise: true, on: board) else {
                    return XCTFail("\(type) failed to rotate in open space")
                }
                XCTAssertEqual(result.kickIndex, 0, "\(type) should not need a kick here")
                XCTAssertEqual(result.piece.origin, piece.origin, "\(type) drifted without a kick")
                piece = result.piece
            }
            XCTAssertEqual(piece.state, .spawn, "\(type) did not come back round")
        }
    }

    func testFourCounterClockwiseRotationsReturnToSpawn() {
        let board = Board()
        for type in TetrominoType.allCases where type != .o {
            var piece = Piece(type: type, origin: openOrigin)
            for _ in 0..<4 {
                guard let result = RotationSystem.rotate(piece, clockwise: false, on: board) else {
                    return XCTFail("\(type) failed to rotate anticlockwise")
                }
                piece = result.piece
            }
            XCTAssertEqual(piece.state, .spawn)
            XCTAssertEqual(piece.origin, openOrigin)
        }
    }

    func testEveryTransitionIsReachableForEveryPiece() {
        let board = Board()
        for type in TetrominoType.allCases where type != .o {
            for start in RotationState.allCases {
                let piece = Piece(type: type, state: start, origin: openOrigin)
                XCTAssertNotNil(RotationSystem.rotate(piece, clockwise: true, on: board),
                                "\(type) \(start) -> clockwise")
                XCTAssertNotNil(RotationSystem.rotate(piece, clockwise: false, on: board),
                                "\(type) \(start) -> anticlockwise")
            }
        }
    }

    /// A vertical I against the right wall cannot rotate flat in place, so
    /// SRS shifts it one column left: the second entry of the I table.
    func testIPieceKicksOffTheRightWall() {
        let board = Board()
        let piece = Piece(type: .i, state: .right, origin: Point(x: 7, y: 10))
        XCTAssertEqual(piece.cells.map(\.x).max(), Board.columns - 1)

        guard let result = RotationSystem.rotate(piece, clockwise: true, on: board) else {
            return XCTFail("the I piece should kick away from the wall")
        }
        XCTAssertEqual(result.kickIndex, 1)
        XCTAssertEqual(result.piece.state, .flipped)
        XCTAssertEqual(result.piece.origin, Point(x: 6, y: 10))
        XCTAssertTrue(board.canPlace(result.piece))
    }

    /// Blocks the first two SRS tests so the rotation has to fall through to
    /// the third, which also lifts the piece one row.
    func testRotationFallsThroughToTheThirdTest() {
        var board = Board()
        board[5, 12] = .i
        board[4, 12] = .i

        let piece = Piece(type: .t, state: .spawn, origin: Point(x: 4, y: 10))
        XCTAssertTrue(board.canPlace(piece))

        guard let result = RotationSystem.rotate(piece, clockwise: true, on: board) else {
            return XCTFail("the third test should have succeeded")
        }
        XCTAssertEqual(result.kickIndex, 2)
        XCTAssertEqual(result.piece.state, .right)
        XCTAssertEqual(result.piece.origin, Point(x: 3, y: 9))
    }

    func testRotationIsRefusedWhenAllFiveTestsCollide() {
        var board = Board()
        let piece = Piece(type: .t, state: .spawn, origin: Point(x: 4, y: 10))
        let free = Set(piece.cells)

        for y in 0..<Board.rows {
            for x in 0..<Board.columns where !free.contains(Point(x: x, y: y)) {
                board[x, y] = .i
            }
        }

        XCTAssertTrue(board.canPlace(piece), "the piece itself must still fit")
        XCTAssertNil(RotationSystem.rotate(piece, clockwise: true, on: board))
        XCTAssertNil(RotationSystem.rotate(piece, clockwise: false, on: board))
    }

    func testEveryShapeHasFourCellsInEveryState() {
        for type in TetrominoType.allCases {
            for state in RotationState.allCases {
                XCTAssertEqual(type.cells(in: state).count, 4, "\(type) \(state)")
                XCTAssertEqual(Set(type.cells(in: state)).count, 4, "\(type) \(state) has duplicates")
            }
        }
    }
}
