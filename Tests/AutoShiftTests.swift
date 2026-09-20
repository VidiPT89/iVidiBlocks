import XCTest
@testable import iTetris

final class AutoShiftTests: XCTestCase {

    private let das = 0.133
    private let arr = 0.033

    private func shift(arr: TimeInterval? = nil) -> AutoShift {
        AutoShift(das: das, arr: arr ?? self.arr)
    }

    /// Runs the clock in 60 Hz slices and adds up everything it asked for.
    private func run(_ machine: inout AutoShift, for seconds: TimeInterval) -> Int {
        let step = 1.0 / 60.0
        var remaining = seconds
        var total = 0
        while remaining > 0 {
            switch machine.tick(deltaTime: min(step, remaining)) {
            case .stay: break
            case let .step(amount): total += amount
            case .slam: total += 99
            }
            remaining -= step
        }
        return total
    }

    func testAFreshPressMovesOnceStraightAway() {
        var machine = shift()
        XCTAssertEqual(machine.setDirection(1), .step(1))
        XCTAssertEqual(machine.direction, 1)
    }

    func testPressingTheSameDirectionAgainChangesNothing() {
        var machine = shift()
        _ = machine.setDirection(-1)
        XCTAssertEqual(machine.setDirection(-1), .stay)
    }

    func testAnyPositiveOrNegativeValueIsTreatedAsOneStep() {
        var machine = shift()
        XCTAssertEqual(machine.setDirection(7), .step(1))
        XCTAssertEqual(machine.setDirection(-7), .step(-1))
    }

    func testNothingRepeatsBeforeTheChargeIsFull() {
        var machine = shift()
        _ = machine.setDirection(1)
        XCTAssertEqual(run(&machine, for: das - 0.02), 0,
                       "the piece must sit still during the DAS window")
    }

    func testRepeatsStartOnceTheChargeCompletes() {
        var machine = shift()
        _ = machine.setDirection(1)
        XCTAssertGreaterThan(run(&machine, for: das + 0.15), 0)
    }

    func testTheRepeatRateSetsHowManyStepsPerSecond() {
        var machine = shift()
        _ = machine.setDirection(1)
        _ = run(&machine, for: das)

        let oneSecond = run(&machine, for: 1.0)
        XCTAssertEqual(Double(oneSecond), 1.0 / arr, accuracy: 3,
                       "roughly one step every ARR")
    }

    func testARepeatRateOfZeroSlamsToTheWall() {
        var machine = shift(arr: 0)
        _ = machine.setDirection(-1)

        var slammed = false
        let step = 1.0 / 60.0
        for _ in 0..<20 {
            if case let .slam(direction) = machine.tick(deltaTime: step) {
                XCTAssertEqual(direction, -1)
                slammed = true
                break
            }
        }
        XCTAssertTrue(slammed)
    }

    func testReleasingStopsEverything() {
        var machine = shift()
        _ = machine.setDirection(1)
        _ = run(&machine, for: das + 0.2)

        machine.release()
        XCTAssertEqual(machine.direction, 0)
        XCTAssertEqual(run(&machine, for: 1.0), 0)
    }

    func testLettingGoAndPressingAgainNeedsAFreshCharge() {
        var machine = shift()
        _ = machine.setDirection(1)
        _ = run(&machine, for: das + 0.2)

        _ = machine.setDirection(0)
        XCTAssertEqual(machine.setDirection(1), .step(1))
        XCTAssertEqual(run(&machine, for: das - 0.02), 0,
                       "the charge must not carry over from the previous press")
    }

    func testAHeldDirectionKeepsSlidingOnTheNextPiece() {
        var machine = shift()
        _ = machine.setDirection(1)
        _ = run(&machine, for: das + 0.1)

        machine.carryOverToNextPiece()
        XCTAssertGreaterThan(run(&machine, for: 1.0 / 60.0), 0,
                            "a held direction should resume immediately, not recharge")
    }

    func testCarryOverDoesNothingWhenNoDirectionIsHeld() {
        var machine = shift()
        machine.carryOverToNextPiece()
        XCTAssertEqual(run(&machine, for: 1.0), 0)
    }

    func testALongStallIsReportedAsOneBatchRatherThanBeingLost() {
        var machine = shift()
        _ = machine.setDirection(1)
        _ = run(&machine, for: das)

        guard case let .step(amount) = machine.tick(deltaTime: arr * 4) else {
            return XCTFail("a long frame should still produce steps")
        }
        XCTAssertEqual(amount, 4)
    }
}
