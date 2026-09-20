import XCTest
@testable import iTetris

final class BoardTests: XCTestCase {

    private func fillRow(_ board: inout Board, _ y: Int, except: [Int] = []) {
        for x in 0..<Board.columns where !except.contains(x) {
            board[x, y] = .i
        }
    }

    func testNewBoardIsEmpty() {
        let board = Board()
        XCTAssertTrue(board.isEmpty())
        XCTAssertTrue(board.completedRows().isEmpty)
        XCTAssertNil(board.highestOccupiedRow())
    }

    func testWallsAndFloorCountAsBlocked() {
        let board = Board()
        XCTAssertTrue(board.isBlocked(x: -1, y: 10))
        XCTAssertTrue(board.isBlocked(x: Board.columns, y: 10))
        XCTAssertTrue(board.isBlocked(x: 5, y: Board.rows))
        XCTAssertFalse(board.isBlocked(x: 5, y: 10))
    }

    func testCompletedRowsDetectsOnlyFullRows() {
        var board = Board()
        fillRow(&board, 21)
        fillRow(&board, 20, except: [4])
        XCTAssertEqual(board.completedRows(), [21])
    }

    func testClearRowCollapsesEverythingAbove() {
        var board = Board()
        fillRow(&board, 21)
        board[0, 20] = .t

        board.clearRows([21])

        XCTAssertNil(board[0, 20], "the marker should have fallen out of row 20")
        XCTAssertEqual(board[0, 21], .t, "and landed on the floor")
        XCTAssertTrue(board.completedRows().isEmpty)
    }

    func testClearingNonAdjacentRowsKeepsRelativeOrder() {
        var board = Board()
        fillRow(&board, 21)
        fillRow(&board, 19)
        board[0, 20] = .t     // sandwiched between the two full rows
        board[1, 18] = .s     // sitting above both

        board.clearRows([19, 21])

        XCTAssertEqual(board[0, 21], .t)
        XCTAssertEqual(board[1, 20], .s)
        XCTAssertEqual(board.cells.compactMap { $0 }.count, 2)
    }

    func testHardDropPositionLandsOnTheFloor() {
        let board = Board()
        let piece = Piece(type: .o, origin: Point(x: 4, y: 0))
        let landed = board.hardDropPosition(of: piece)
        XCTAssertEqual(landed.cells.map(\.y).max(), Board.rows - 1)
    }

    func testHardDropPositionStacksOnExistingBlocks() {
        var board = Board()
        fillRow(&board, 21)
        let piece = Piece(type: .o, origin: Point(x: 4, y: 0))
        let landed = board.hardDropPosition(of: piece)
        XCTAssertEqual(landed.cells.map(\.y).max(), Board.rows - 2)
    }

    func testHighestOccupiedRow() {
        var board = Board()
        board[3, 15] = .z
        board[7, 9] = .l
        XCTAssertEqual(board.highestOccupiedRow(), 9)
    }
}
