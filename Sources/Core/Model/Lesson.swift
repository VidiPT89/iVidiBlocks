import Foundation

/// One guided practice drill: a prepared stack, a short fixed run of
/// pieces and a single technique to pull off with them. Lessons go from
/// the first hard drop up to back-to-back quads, so the scoring ideas in
/// How to play can be tried on a board built to make them possible.
struct Lesson: Identifiable, Equatable {

    enum Goal: Equatable {
        /// Clear at least one row.
        case clearLine
        /// Put the first piece on hold, then clear a row.
        case holdThenClear
        /// Clear this many rows with a single piece.
        case clearAtOnce(Int)
        /// Clear rows with a T-spin.
        case tSpinClear
        /// Keep a combo going for this many pieces after the first clear.
        case combo(Int)
        /// Follow one difficult clear with another.
        case backToBack
    }

    let id: String
    let titleKey: LocKey
    let instructionKey: LocKey
    let goal: Goal
    /// Every piece the lesson deals, in order. Running out without meeting
    /// the goal fails the attempt.
    let pieces: [TetrominoType]
    /// The prepared stack from the floor upwards, `X` for a block and `.`
    /// for a gap. Ten characters per row.
    let rows: [String]

    var board: Board {
        var board = Board()
        for (offset, row) in rows.enumerated() {
            let y = Board.rows - 1 - offset
            for (x, mark) in row.enumerated() where mark == "X" {
                board[x, y] = .z
            }
        }
        return board
    }

    var next: Lesson? {
        guard let index = Lesson.all.firstIndex(of: self),
              index + 1 < Lesson.all.count else { return nil }
        return Lesson.all[index + 1]
    }

    static let all: [Lesson] = [
        Lesson(id: "drop", titleKey: .lessonDrop, instructionKey: .lessonDropHint,
               goal: .clearLine, pieces: [.i],
               rows: ["XXX....XXX"]),
        Lesson(id: "rotate", titleKey: .lessonRotate, instructionKey: .lessonRotateHint,
               goal: .clearLine, pieces: [.i],
               rows: ["XXXXXXXXX."]),
        Lesson(id: "hold", titleKey: .lessonHold, instructionKey: .lessonHoldHint,
               goal: .holdThenClear, pieces: [.o, .i],
               rows: ["XXX....XXX"]),
        Lesson(id: "quad", titleKey: .lessonQuad, instructionKey: .lessonQuadHint,
               goal: .clearAtOnce(4), pieces: [.i],
               rows: ["X.XXXXXXXX",
                      "XXXXXXX.XX",
                      ".XXXXXXXXX",
                      ".XXXXXXXXX",
                      ".XXXXXXXXX",
                      ".XXXXXXXXX"]),
        Lesson(id: "tspin", titleKey: .lessonTSpin, instructionKey: .lessonTSpinHint,
               goal: .tSpinClear, pieces: [.t],
               rows: ["XXXX.XXXXX",
                      "XXX...XXXX",
                      "XXX..XXXXX"]),
        Lesson(id: "combo", titleKey: .lessonCombo, instructionKey: .lessonComboHint,
               goal: .combo(2), pieces: [.o, .o, .o],
               rows: ["..XXXXXXXX",
                      "..XXXXXXXX",
                      "..XXXXXXXX",
                      "..XXXXXXXX",
                      "..XXXXXXXX",
                      "..XXXXXXXX"]),
        Lesson(id: "b2b", titleKey: .lessonBackToBack, instructionKey: .lessonBackToBackHint,
               goal: .backToBack, pieces: [.i, .i],
               rows: Array(repeating: "XXXXXXXXX.", count: 8))
    ]
}

/// Deals a lesson's pieces in its fixed order, over and over. The tracker
/// ends the attempt once the real ones are used up, so the repeats only
/// keep the preview queue full.
struct LessonPieces: PieceRandomSource {
    let order: [TetrominoType]
    func shuffle(_ pieces: inout [TetrominoType]) { pieces = order }
}

/// Watches the engine's events and decides when a lesson is won or lost.
struct LessonTracker {

    enum Outcome: Equatable {
        case inProgress
        case passed
        case failed
    }

    let lesson: Lesson
    private(set) var outcome: Outcome = .inProgress
    private var locked = 0
    private var held = false

    init(lesson: Lesson) {
        self.lesson = lesson
    }

    mutating func observe(_ event: GameEvent) {
        guard outcome == .inProgress else { return }
        switch event {
        case .holdSwapped:
            held = true
        case let .linesCleared(_, result) where meetsGoal(result):
            outcome = .passed
        case .locked:
            locked += 1
        case .gameOver:
            outcome = .failed
        default:
            break
        }
    }

    /// Called once the frame's events are in, so a clear reported after its
    /// lock still counts before the attempt is judged out of pieces.
    mutating func settle() {
        if outcome == .inProgress, locked >= lesson.pieces.count { outcome = .failed }
    }

    private func meetsGoal(_ result: ClearOutcome) -> Bool {
        switch lesson.goal {
        case .clearLine: return result.lines > 0
        case .holdThenClear: return held && result.lines > 0
        case let .clearAtOnce(count): return result.lines >= count
        case .tSpinClear: return result.spin != .none && result.lines > 0
        case let .combo(length): return result.combo >= length
        case .backToBack: return result.backToBack
        }
    }
}
