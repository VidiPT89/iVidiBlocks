import Foundation

/// One guided practice drill: a prepared well, a short fixed run of shards
/// and a single idea to pull off with them. Lessons go from the first drop
/// to cascades and the core pulse, so each rule in How to play can be tried
/// on a well built to make it possible.
struct Lesson: Identifiable, Equatable {

    enum Goal: Equatable {
        /// Close at least one full ring.
        case clearRing
        /// Fuse an arc of one colour.
        case clearArc
        /// Set off a cascade at least this many links long.
        case chain(Int)
        /// Spend the core charge.
        case pulse
    }

    let id: String
    let titleKey: LocKey
    let instructionKey: LocKey
    let goal: Goal
    /// Every shard the lesson deals, in order. Running out without meeting
    /// the goal fails the attempt.
    let pieces: [Shard]
    /// The prepared well from the core outwards, one character per sector:
    /// `e` ember, `a` amber, `t` tide and `.` for a gap. Sixteen per ring.
    let rings: [String]
    /// Whether the core starts fully charged.
    var charged = false

    var board: Board {
        var board = Board()
        for (offset, ring) in rings.enumerated() {
            let y = Board.rings - 1 - offset
            for (x, mark) in ring.enumerated() {
                board[x, y] = Lesson.color(for: mark)
            }
        }
        return board
    }

    private static func color(for mark: Character) -> ShardColor? {
        switch mark {
        case "e": return .ember
        case "a": return .amber
        case "t": return .tide
        default: return nil
        }
    }

    var next: Lesson? {
        guard let index = Lesson.all.firstIndex(of: self),
              index + 1 < Lesson.all.count else { return nil }
        return Lesson.all[index + 1]
    }

    static let all: [Lesson] = [
        Lesson(id: "drop", titleKey: .lessonDrop, instructionKey: .lessonDropHint,
               goal: .clearRing, pieces: [Shard(shape: .duo, color: .amber)],
               rings: ["..tetatetatetate"]),
        Lesson(id: "spin", titleKey: .lessonSpin, instructionKey: .lessonSpinHint,
               goal: .clearRing, pieces: [Shard(shape: .duo, color: .amber)],
               rings: ["tetateta..tetate"]),
        Lesson(id: "rotate", titleKey: .lessonRotate, instructionKey: .lessonRotateHint,
               goal: .clearRing, pieces: [Shard(shape: .duo, color: .tide)],
               rings: ["teta.atetatetate",
                       "etat.tetatetatet"]),
        Lesson(id: "arc", titleKey: .lessonArc, instructionKey: .lessonArcHint,
               goal: .clearArc, pieces: [Shard(shape: .duo, color: .amber)],
               rings: ["..aaatetet.tetet"]),
        Lesson(id: "chain", titleKey: .lessonChain, instructionKey: .lessonChainHint,
               goal: .chain(2), pieces: [Shard(shape: .duo, color: .amber)],
               rings: ["..aaattte.etaeae",
                       "..ttt..........."]),
        Lesson(id: "pulse", titleKey: .lessonPulse, instructionKey: .lessonPulseHint,
               goal: .pulse,
               pieces: Array(repeating: Shard(shape: .spark, color: .ember), count: 3),
               rings: ["teta.etat.eta.et",
                       "a.et.at.ea.te.ta",
                       "et.a.te..at.e.t."],
               charged: true)
    ]
}

/// Deals a lesson's shards in its fixed order, over and over. The tracker
/// ends the attempt once the real ones are used up, so the repeats only
/// keep the preview queue full.
struct LessonPieces: PieceRandomSource {
    let order: [Shard]
    func shuffle(_ shards: inout [Shard]) { shards = order }
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

    init(lesson: Lesson) {
        self.lesson = lesson
    }

    mutating func observe(_ event: GameEvent) {
        guard outcome == .inProgress else { return }
        switch event {
        case let .cleared(_, _, result) where meetsGoal(result):
            outcome = .passed
        case .pulsed where lesson.goal == .pulse:
            outcome = .passed
        case .locked:
            locked += 1
        case .gameOver:
            outcome = .failed
        default:
            break
        }
    }

    /// Called once the frame's events are in. An attempt that has used all
    /// its shards fails, but only after any cascade it started has played
    /// out, since a later link may still meet the goal.
    mutating func settle(cascading: Bool) {
        if outcome == .inProgress, !cascading, locked >= lesson.pieces.count {
            outcome = .failed
        }
    }

    private func meetsGoal(_ result: ClearOutcome) -> Bool {
        switch lesson.goal {
        case .clearRing: return result.rings > 0
        case .clearArc: return result.arcs > 0
        case let .chain(length): return result.chain >= length
        case .pulse: return false
        }
    }
}
