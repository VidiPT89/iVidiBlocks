import XCTest
@testable import iVidiBlocks

/// The circular well: wrapping sectors, what counts as a ring or an arc,
/// and how cells slide inwards once something clears.
final class BoardTests: XCTestCase {

    private let core = Board.rings - 1

    private func ring(_ marks: String, at y: Int, on board: inout Board) {
        for (x, mark) in marks.enumerated() {
            switch mark {
            case "e": board[x, y] = .ember
            case "a": board[x, y] = .amber
            case "t": board[x, y] = .tide
            default: board[x, y] = nil
            }
        }
    }

    func testSectorsWrapAroundTheCircle() {
        XCTAssertEqual(Board.wrap(-1), Board.sectors - 1)
        XCTAssertEqual(Board.wrap(Board.sectors), 0)
        var board = Board()
        board[-1, core] = .amber
        XCTAssertEqual(board[Board.sectors - 1, core], .amber)
    }

    func testTheCoreAndTheSpaceOutsideTheBufferAreSolid() {
        let board = Board()
        XCTAssertTrue(board.isBlocked(x: 0, y: Board.rings))
        XCTAssertTrue(board.isBlocked(x: 0, y: -1))
        XCTAssertFalse(board.isBlocked(x: 0, y: 0))
    }

    func testAPieceAcrossSectorZeroOccupiesBothEnds() {
        let piece = Piece(shard: Shard(shape: .duo, color: .tide), origin: Point(x: Board.sectors - 1, y: 4))
        XCTAssertEqual(Set(piece.cells.map(\.x)), [Board.sectors - 1, 0])
    }

    func testAFullRingClearsWhateverItsColours() {
        var board = Board()
        ring("eatteatteatteatt", at: core, on: &board)
        let scan = board.scan()
        XCTAssertEqual(scan.rings, 1)
        XCTAssertEqual(scan.arcs, 0)
        XCTAssertEqual(scan.cells.count, Board.sectors)
    }

    func testFiveOfOneColourFuseIntoAnArcInAnOpenRing() {
        var board = Board()
        ring("aaaaa.te........", at: core, on: &board)
        let scan = board.scan()
        XCTAssertEqual(scan.rings, 0)
        XCTAssertEqual(scan.arcs, 1)
        XCTAssertEqual(scan.cells, Set((0..<5).map { Point(x: $0, y: core) }))
    }

    func testFourOfAColourIsNotAnArc() {
        var board = Board()
        ring("aaaa.aaaa.......", at: core, on: &board)
        XCTAssertTrue(board.scan().isEmpty)
    }

    func testAnArcCanRunAcrossSectorZero() {
        var board = Board()
        ring("ttt..........ttt", at: core, on: &board)
        XCTAssertEqual(board.scan().arcs, 1)
        XCTAssertEqual(board.scan().cells.count, 6)
    }

    func testARingOfOneColourIsBothARingAndAnArc() {
        var board = Board()
        ring(String(repeating: "e", count: Board.sectors), at: core, on: &board)
        let scan = board.scan()
        XCTAssertEqual(scan.rings, 1)
        XCTAssertEqual(scan.arcs, 1)
    }

    func testTheBufferNeverClears() {
        var board = Board()
        ring("aaaaa...........", at: 0, on: &board)
        XCTAssertTrue(board.scan().isEmpty)
    }

    func testOnlyCellsOutsideARemovedCellSlideInwards() {
        var board = Board()
        board[0, core] = .amber
        board[0, core - 1] = .tide
        board[1, core - 1] = .ember     // an overhang over an existing gap
        board.remove([Point(x: 0, y: core)])
        XCTAssertEqual(board[0, core], .tide)
        XCTAssertNil(board[0, core - 1])
        XCTAssertNil(board[1, core], "a gap that was already there stays")
        XCTAssertEqual(board[1, core - 1], .ember)
    }

    func testRemovingTwoRingsDropsTheRestByTwo() {
        var board = Board()
        ring("eatteatteatteatt", at: core, on: &board)
        ring("teatteatteatteat", at: core - 1, on: &board)
        board[3, core - 2] = .amber
        board.remove(board.scan().cells)
        XCTAssertEqual(board[3, core], .amber)
        XCTAssertEqual(board.cells.compactMap { $0 }.count, 1)
    }

    func testDropPositionStopsOnTheCoreOrOnCells() {
        var board = Board()
        let piece = Piece(shard: Shard(shape: .spark, color: .ember), origin: Point(x: 5, y: 1))
        XCTAssertEqual(board.dropPosition(of: piece).origin.y, core)
        board[5, core] = .tide
        XCTAssertEqual(board.dropPosition(of: piece).origin.y, core - 1)
    }

    // MARK: Shapes and turning

    func testShapesKeepTheirSizeInEveryState() {
        for shape in ShardShape.allCases {
            let sizes = Set(RotationState.allCases.map { shape.cells(in: $0).count })
            XCTAssertEqual(sizes.count, 1, "\(shape)")
            XCTAssertLessThanOrEqual(sizes.first ?? 0, 3, "no shard is a tetromino")
        }
    }

    func testFourQuarterTurnsComeBackToTheStart() {
        for shape in ShardShape.allCases {
            XCTAssertEqual(Set(shape.cells(in: .spawn)),
                           Set(shape.cells(in: RotationState.left.clockwise)))
        }
    }

    func testATurnStandsATrioOnEnd() {
        let cells = ShardShape.trio.cells(in: .right)
        XCTAssertEqual(Set(cells.map(\.x)), [0])
        XCTAssertEqual(Set(cells.map(\.y)), [-1, 0, 1])
    }

    func testASparkHasNothingToTurn() {
        let spark = Piece(shard: Shard(shape: .spark, color: .amber), origin: Point(x: 3, y: 4))
        XCTAssertNil(RotationSystem.rotate(spark, clockwise: true, on: Board()))
    }

    func testABlockedTurnIsNudgedSideways() throws {
        var board = Board()
        let trio = Piece(shard: Shard(shape: .trio, color: .tide), origin: Point(x: 4, y: core - 1))
        board[4, core] = .ember   // right under the pivot
        let result = try XCTUnwrap(RotationSystem.rotate(trio, clockwise: true, on: board))
        XCTAssertNotEqual(result.kickIndex, 0)
        XCTAssertTrue(board.canPlace(result.piece))
    }
}
