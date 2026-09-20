import XCTest
@testable import iTetris

final class SpinDetectorTests: XCTestCase {

    /// A T pointing up at (4,10). Its 3x3 corners are (4,10), (6,10),
    /// (4,12) and (6,12); the two front corners are the pair on the top row.
    private let origin = Point(x: 4, y: 10)

    private func board(filling corners: [Point]) -> Board {
        var board = Board()
        for corner in corners { board[corner.x, corner.y] = .i }
        return board
    }

    private func detect(on board: Board,
                        state: RotationState = .spawn,
                        type: TetrominoType = .t,
                        rotated: Bool = true,
                        kickIndex: Int = 0) -> SpinKind {
        SpinDetector.detect(piece: Piece(type: type, state: state, origin: origin),
                            lastActionWasRotation: rotated,
                            kickIndex: kickIndex,
                            board: board)
    }

    func testBothFrontCornersOccupiedIsAFullTSpin() {
        let board = board(filling: [Point(x: 4, y: 10),
                                    Point(x: 6, y: 10),
                                    Point(x: 4, y: 12)])
        XCTAssertEqual(detect(on: board), .full)
    }

    func testOneFrontCornerOccupiedIsAMini() {
        let board = board(filling: [Point(x: 4, y: 10),
                                    Point(x: 4, y: 12),
                                    Point(x: 6, y: 12)])
        XCTAssertEqual(detect(on: board), .mini)
    }

    func testTheFifthKickPromotesAMiniToAFullTSpin() {
        let board = board(filling: [Point(x: 4, y: 10),
                                    Point(x: 4, y: 12),
                                    Point(x: 6, y: 12)])
        XCTAssertEqual(detect(on: board, kickIndex: 4), .full)
    }

    func testTwoOccupiedCornersIsNotASpin() {
        let board = board(filling: [Point(x: 4, y: 10), Point(x: 6, y: 10)])
        XCTAssertEqual(detect(on: board), .none)
    }

    func testAMoveRatherThanARotationIsNotASpin() {
        let board = board(filling: [Point(x: 4, y: 10),
                                    Point(x: 6, y: 10),
                                    Point(x: 4, y: 12)])
        XCTAssertEqual(detect(on: board, rotated: false), .none)
    }

    func testOnlyTheTPieceCanSpin() {
        let board = board(filling: [Point(x: 4, y: 10),
                                    Point(x: 6, y: 10),
                                    Point(x: 4, y: 12),
                                    Point(x: 6, y: 12)])
        for type in TetrominoType.allCases where type != .t {
            XCTAssertEqual(detect(on: board, type: type), .none, "\(type) must not spin")
        }
    }

    /// The floor counts as solid, so a T resting on the bottom row already
    /// has its two rear corners occupied by the edge of the board.
    func testTheFloorCountsAsOccupiedCorners() {
        let seated = Point(x: 4, y: 20)   // corners at y = 22 fall off the board
        var board = Board()

        func detect() -> SpinKind {
            SpinDetector.detect(piece: Piece(type: .t, state: .spawn, origin: seated),
                                lastActionWasRotation: true,
                                kickIndex: 0,
                                board: board)
        }

        XCTAssertEqual(detect(), .none, "two floor corners alone are not enough")

        board[4, 20] = .i
        XCTAssertEqual(detect(), .mini, "one front corner plus the floor is a mini")

        board[6, 20] = .i
        XCTAssertEqual(detect(), .full, "both front corners make it a full T-spin")
    }
}
