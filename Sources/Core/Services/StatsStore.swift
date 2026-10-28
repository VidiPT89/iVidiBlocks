import Foundation
import Combine

/// Best result for one mode. Marathon and Ultra rank on score, Sprint ranks
/// on the fastest time to clear its 40 lines.
struct ModeRecord: Codable, Equatable {
    var score: Int = 0
    var lines: Int = 0
    var level: Int = 1
    var time: TimeInterval = 0
    var achievedAt: Date = .distantPast

    var isSet: Bool { achievedAt != .distantPast }
}

struct LifetimeStats: Codable, Equatable {
    var gamesPlayed = 0
    var piecesPlaced = 0
    var linesCleared = 0
    var quads = 0
    var tSpins = 0
    var timePlayed: TimeInterval = 0
    /// Longest chain of consecutive clearing pieces across every run.
    var bestCombo = 0
}

extension LifetimeStats {
    /// Missing counters read as zero, so adding one never costs a player
    /// the history saved by an earlier build.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try c.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        piecesPlaced = try c.decodeIfPresent(Int.self, forKey: .piecesPlaced) ?? 0
        linesCleared = try c.decodeIfPresent(Int.self, forKey: .linesCleared) ?? 0
        quads = try c.decodeIfPresent(Int.self, forKey: .quads) ?? 0
        tSpins = try c.decodeIfPresent(Int.self, forKey: .tSpins) ?? 0
        timePlayed = try c.decodeIfPresent(TimeInterval.self, forKey: .timePlayed) ?? 0
        bestCombo = try c.decodeIfPresent(Int.self, forKey: .bestCombo) ?? 0
    }
}

private struct StatsPayload: Codable {
    var records: [String: ModeRecord] = [:]
    var lifetime = LifetimeStats()
    var completedLessons: [String] = []

    init(records: [String: ModeRecord], lifetime: LifetimeStats, completedLessons: [String]) {
        self.records = records
        self.lifetime = lifetime
        self.completedLessons = completedLessons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([String: ModeRecord].self, forKey: .records) ?? [:]
        lifetime = try c.decodeIfPresent(LifetimeStats.self, forKey: .lifetime) ?? LifetimeStats()
        completedLessons = try c.decodeIfPresent([String].self, forKey: .completedLessons) ?? []
    }
}

/// Records and lifetime totals, kept as one JSON file in Documents. Saves
/// are debounced and run off the main thread so a write never lands in the
/// middle of a frame.
final class StatsStore: ObservableObject {

    @Published private(set) var records: [GameMode: ModeRecord] = [:]
    @Published private(set) var lifetime = LifetimeStats()
    /// Ids of the practice lessons passed at least once.
    @Published private(set) var completedLessons: Set<String> = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.ividi.ividiblocks.stats", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("stats.json")
        load()
    }

    func record(for mode: GameMode) -> ModeRecord? {
        guard let record = records[mode], record.isSet else { return nil }
        return record
    }

    /// Folds a finished run into the stored history.
    /// - Returns: `true` when the run beat the existing record for its mode.
    @discardableResult
    func submit(mode: GameMode,
                score: Int,
                lines: Int,
                level: Int,
                time: TimeInterval,
                reason: GameOverReason,
                runStats: RunStats) -> Bool {
        lifetime.gamesPlayed += 1
        lifetime.piecesPlaced += runStats.piecesPlaced
        lifetime.linesCleared += runStats.linesCleared
        lifetime.quads += runStats.quads
        lifetime.tSpins += runStats.tSpins
        lifetime.timePlayed += time
        lifetime.bestCombo = max(lifetime.bestCombo, runStats.maxCombo)

        let candidate = ModeRecord(score: score, lines: lines, level: level,
                                   time: time, achievedAt: Date())
        let beaten = isBetter(candidate, than: records[mode], mode: mode, reason: reason)
        if beaten { records[mode] = candidate }

        scheduleSave()
        return beaten
    }

    func completeLesson(_ lesson: Lesson) {
        guard completedLessons.insert(lesson.id).inserted else { return }
        scheduleSave()
    }

    func reset() {
        records = [:]
        lifetime = LifetimeStats()
        completedLessons = []
        scheduleSave()
    }

    private func isBetter(_ candidate: ModeRecord,
                          than existing: ModeRecord?,
                          mode: GameMode,
                          reason: GameOverReason) -> Bool {
        switch mode.scoring {
        case .highestScore:
            // A run that scored nothing is not an achievement, and showing
            // "Best 0" under a mode nobody has really played reads as a bug.
            guard candidate.score > 0 else { return false }
            guard let existing, existing.isSet else { return true }
            return candidate.score > existing.score
        case .fastestTime:
            // An unfinished Sprint has no meaningful time to record.
            guard reason == .targetReached else { return false }
            guard let existing, existing.isSet else { return true }
            return candidate.time < existing.time
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(StatsPayload.self, from: data) else {
            return
        }
        lifetime = payload.lifetime
        completedLessons = Set(payload.completedLessons)
        records = payload.records.reduce(into: [:]) { result, entry in
            if let mode = GameMode(rawValue: entry.key) { result[mode] = entry.value }
        }
    }

    private var payload: StatsPayload {
        StatsPayload(records: records.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
                     lifetime: lifetime,
                     completedLessons: completedLessons.sorted())
    }

    private static func write(_ payload: StatsPayload, to url: URL) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = payload
        let url = fileURL
        let item = DispatchWorkItem { StatsStore.write(snapshot, to: url) }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    /// Flushes any pending write immediately, for when the app backgrounds.
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = payload
        // Serialize with any write already running before the flush.
        queue.sync { StatsStore.write(snapshot, to: fileURL) }
    }
}
